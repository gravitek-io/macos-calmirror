import Foundation

/// Manages persistence of sync records as JSON files, one file per mirror rule.
///
/// Each rule's source-to-blocker event mappings are stored in a separate JSON file
/// under `~/Library/Application Support/CalMirror/sync/`. This isolation means
/// deleting a rule is as simple as deleting its file.
///
/// All writes are atomic to prevent corruption from interrupted writes
/// (e.g., process killed mid-write, system sleep). The single-writer guarantee
/// is provided by the launchd agent running sync cycles sequentially.
public final class SyncRecordStore {

    public enum ReadError: Error, LocalizedError {
        case unreadable(URL, Error)
        public var errorDescription: String? {
            switch self {
            case .unreadable(let url, let error):
                return "Could not read sync mappings at \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    /// Root directory for sync record files (one JSON file per rule).
    private let baseDirectory: URL
    private let writeData: (Data, URL) throws -> Void

    /// Shared encoder configured for human-readable ISO 8601 date output.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    /// Shared decoder configured to parse ISO 8601 dates.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialization

    /// Initializes the store with the default application support directory.
    ///
    /// The directory `~/Library/Application Support/CalMirror/sync/` is created
    /// if it does not already exist.
    ///
    /// - Throws: If the application support directory cannot be resolved
    ///   or the sync directory cannot be created.
    public init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.baseDirectory = appSupport
            .appendingPathComponent("CalMirror", isDirectory: true)
            .appendingPathComponent("sync", isDirectory: true)
        self.writeData = { data, url in try data.write(to: url, options: .atomic) }
        try Self.ensureDirectoryExists(baseDirectory)
    }

    /// Initializes the store with a custom base directory.
    ///
    /// Intended for testing to avoid polluting the real application support directory.
    ///
    /// - Parameter baseDirectory: The directory where sync record JSON files will be stored.
    /// - Throws: If the directory cannot be created.
    internal init(baseDirectory: URL) throws {
        self.baseDirectory = baseDirectory
        self.writeData = { data, url in try data.write(to: url, options: .atomic) }
        try Self.ensureDirectoryExists(baseDirectory)
    }

    /// Injectable file writer for deterministic persistence-failure tests.
    internal init(baseDirectory: URL, writeHandler: @escaping (Data, URL) throws -> Void) throws {
        self.baseDirectory = baseDirectory
        self.writeData = writeHandler
        try Self.ensureDirectoryExists(baseDirectory)
    }

    // MARK: - Public Methods

    /// Loads all sync records for a given mirror rule.
    ///
    /// Reads and decodes the JSON file at `{baseDirectory}/{ruleId}.json`.
    /// Returns an empty array if the file does not exist, allowing callers
    /// to treat a missing file the same as an empty record set.
    ///
    /// - Parameter ruleId: The unique identifier of the mirror rule.
    /// - Returns: The decoded array of sync records, or an empty array if the file is absent.
    public func loadRecords(for ruleId: UUID) -> [SyncRecord] {
        (try? loadRecordsChecked(for: ruleId)) ?? []
    }

    /// Loads mappings while distinguishing an absent first-run file from corrupt or unreadable state.
    public func loadRecordsChecked(for ruleId: UUID) throws -> [SyncRecord] {
        let url = filePath(for: ruleId)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            do { return try decoder.decode([SyncRecord].self, from: data) }
            catch { throw ReadError.unreadable(url, error) }
        } catch {
            if let readError = error as? ReadError { throw readError }
            throw ReadError.unreadable(url, error)
        }
    }

    /// Returns blocker IDs owned by mappings for every other rule. Used to
    /// prevent a sync rule from adopting an event that another rule references.
    func blockerIdentifiersOwned(byRulesOtherThan ruleID: UUID) throws -> (local: Set<String>, external: Set<String>) {
        let files = try FileManager.default.contentsOfDirectory(
            at: baseDirectory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        var local = Set<String>()
        var external = Set<String>()
        for file in files {
            guard let ownerID = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  ownerID != ruleID else { continue }
            let data: Data
            do { data = try Data(contentsOf: file) }
            catch { throw ReadError.unreadable(file, error) }
            let records: [SyncRecord]
            do { records = try decoder.decode([SyncRecord].self, from: data) }
            catch { throw ReadError.unreadable(file, error) }
            local.formUnion(records.map(\.blockerEventIdentifier))
            external.formUnion(records.map(\.blockerExternalIdentifier))
        }
        return (local, external)
    }

    /// Persists sync records for a given mirror rule as a JSON file.
    ///
    /// Encodes the records and writes them atomically to `{baseDirectory}/{ruleId}.json`.
    /// Atomic writes ensure the file is never left in a partially-written state.
    ///
    /// - Parameters:
    ///   - records: The array of sync records to persist.
    ///   - ruleId: The unique identifier of the mirror rule.
    /// - Throws: If encoding fails or the file cannot be written.
    public func saveRecords(_ records: [SyncRecord], for ruleId: UUID) throws {
        let url = filePath(for: ruleId)
        let data = try encoder.encode(records)
        try writeData(data, url)
    }

    /// Deletes the sync records file for a given mirror rule.
    ///
    /// Removes the JSON file at `{baseDirectory}/{ruleId}.json`. Does nothing
    /// if the file does not exist, making this operation idempotent and safe
    /// to call during rule cleanup regardless of prior state.
    ///
    /// - Parameter ruleId: The unique identifier of the mirror rule.
    /// - Throws: If the file exists but cannot be deleted.
    public func deleteRecords(for ruleId: UUID) throws {
        let url = filePath(for: ruleId)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }

    /// Returns the file URL where sync records for a given rule are stored.
    ///
    /// The path follows the pattern `{baseDirectory}/{ruleId}.json`,
    /// using the UUID's lowercase string representation as the filename.
    ///
    /// - Parameter ruleId: The unique identifier of the mirror rule.
    /// - Returns: The file URL for the rule's sync records.
    public func filePath(for ruleId: UUID) -> URL {
        baseDirectory.appendingPathComponent("\(ruleId.uuidString).json")
    }

    // MARK: - Private Helpers

    /// Creates the directory at the given URL if it does not already exist.
    ///
    /// Uses `withIntermediateDirectories: true` to create any missing
    /// parent directories in the path.
    ///
    /// - Parameter url: The directory URL to ensure exists.
    /// - Throws: If the directory cannot be created.
    private static func ensureDirectoryExists(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
    }
}
