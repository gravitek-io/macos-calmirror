import XCTest
@testable import CalmMirrorCore

/// Unit tests for `ContentHasher` (T017).
///
/// Validates that the SHA-256 content hashing behaves deterministically,
/// produces correctly formatted output, and is sensitive to each input field.
final class ContentHasherTests: XCTestCase {

    // MARK: - Fixed Fixtures

    /// Wednesday 2024-01-31 00:00:00 UTC
    private let fixedStart = Date(timeIntervalSince1970: 1_706_616_000)
    /// Wednesday 2024-01-31 01:00:00 UTC (one hour later)
    private let fixedEnd = Date(timeIntervalSince1970: 1_706_619_600)

    // MARK: - Determinism

    /// Calling `computeContentHash` multiple times with identical inputs must
    /// return the exact same hash every time.
    func testDeterminism() {
        let hash1 = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: false
        )
        let hash2 = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: false
        )
        let hash3 = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: false
        )

        XCTAssertEqual(hash1, hash2, "Hash must be deterministic across calls")
        XCTAssertEqual(hash2, hash3, "Hash must be deterministic across calls")
    }

    // MARK: - Input Sensitivity

    /// A different `startDate` must produce a different hash.
    func testDifferentStartDateProducesDifferentHash() {
        let hashA = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: false
        )
        let altStart = Date(timeIntervalSince1970: 1_706_616_060) // +60 s
        let hashB = ContentHasher.computeContentHash(
            startDate: altStart, endDate: fixedEnd, isAllDay: false
        )

        XCTAssertNotEqual(hashA, hashB, "Changing startDate must change the hash")
    }

    /// A different `endDate` must produce a different hash.
    func testDifferentEndDateProducesDifferentHash() {
        let hashA = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: false
        )
        let altEnd = Date(timeIntervalSince1970: 1_706_619_660) // +60 s
        let hashB = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: altEnd, isAllDay: false
        )

        XCTAssertNotEqual(hashA, hashB, "Changing endDate must change the hash")
    }

    /// Toggling `isAllDay` must produce a different hash.
    func testDifferentIsAllDayProducesDifferentHash() {
        let hashA = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: false
        )
        let hashB = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: true
        )

        XCTAssertNotEqual(hashA, hashB, "Toggling isAllDay must change the hash")
    }

    /// Same start and end dates but different `isAllDay` flag must yield
    /// different hashes — confirms the boolean is included in the digest.
    func testIdenticalDatesWithDifferentAllDay() {
        let hashFalse = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: false
        )
        let hashTrue = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: true
        )

        XCTAssertNotEqual(
            hashFalse, hashTrue,
            "Same dates with different isAllDay must produce different hashes"
        )
    }

    // MARK: - Output Format

    /// A SHA-256 digest encoded as hex must be exactly 64 characters long
    /// (32 bytes * 2 hex chars per byte).
    func testHashLength() {
        let hash = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: false
        )

        XCTAssertEqual(hash.count, 64, "SHA-256 hex string must be 64 characters")
    }

    /// The hash string must contain only lowercase hexadecimal characters.
    func testHashFormat() {
        let hash = ContentHasher.computeContentHash(
            startDate: fixedStart, endDate: fixedEnd, isAllDay: true
        )
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        let nonHexChars = CharacterSet(charactersIn: hash).subtracting(hexCharacterSet)

        XCTAssertTrue(
            nonHexChars.isEmpty,
            "Hash must only contain lowercase hex characters [0-9a-f], got: \(hash)"
        )
    }
}
