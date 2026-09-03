import XCTest
@testable import CalmMirrorCore

/// Placeholder test to validate the test target builds and links correctly.
final class CalmMirrorCoreTests: XCTestCase {
    func testCoreLibraryVersion() {
        XCTAssertEqual(CalmMirrorCore.version, "1.1.0")
    }
}
