import Darwin
import Foundation

/// Cross-process serialization for calendar and configuration mutations.
/// The lock file is intentionally stable and is never removed or replaced.
public final class ProcessMutationLock {
    public enum LockError: Error, LocalizedError {
        case busy
        case system(String)
        public var errorDescription: String? {
            switch self {
            case .busy: return "Another CalMirror operation is changing calendars or rules. Try again shortly."
            case .system(let message): return "Could not acquire the CalMirror mutation lock: \(message)"
            }
        }
    }

    private let descriptor: Int32
    private var released = false

    private init(descriptor: Int32) { self.descriptor = descriptor }

    public static func acquire(wait: Bool = true) throws -> ProcessMutationLock {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("CalMirror", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try acquire(at: directory.appendingPathComponent("mutation.lock"), wait: wait)
    }

    static func acquire(at url: URL, wait: Bool) throws -> ProcessMutationLock {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let path = url.path
        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LockError.system(String(cString: strerror(errno))) }
        let operation = LOCK_EX | (wait ? 0 : LOCK_NB)
        if flock(fd, operation) != 0 {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK || code == EAGAIN { throw LockError.busy }
            throw LockError.system(String(cString: strerror(code)))
        }
        return ProcessMutationLock(descriptor: fd)
    }

    public func release() {
        guard !released else { return }
        released = true
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
    }

    deinit { release() }
}
