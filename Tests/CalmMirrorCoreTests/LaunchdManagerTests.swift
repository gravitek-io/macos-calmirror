import Foundation
import XCTest
@testable import CalmMirrorCore

final class LaunchdManagerTests: XCTestCase {
    func testIntervalUpdateWritesScheduleWithoutRunAtLoad() throws {
        let fixture = try makeFixture()
        var commands: [[String]] = []
        let manager = LaunchdManager(plistURL: fixture.plistURL, preferences: fixture.defaults) { commands.append($0) }

        try manager.setSyncInterval(1800)

        let plist = try XCTUnwrap(NSDictionary(contentsOf: fixture.plistURL) as? [String: Any])
        XCTAssertEqual(plist["StartInterval"] as? Int, 1800)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
        XCTAssertEqual(fixture.defaults.integer(forKey: LaunchdManager.syncIntervalPreferenceKey), 1800)
        XCTAssertEqual(commands.count, 2)
        XCTAssertTrue(commands[0].first == "bootout")
        XCTAssertTrue(commands[1].first == "bootstrap")
        XCTAssertFalse(commands.contains { $0.first == "kickstart" })
    }

    func testUnsupportedIntervalDoesNotChangePreferenceOrPlist() throws {
        let fixture = try makeFixture()
        let original = try Data(contentsOf: fixture.plistURL)
        let manager = LaunchdManager(plistURL: fixture.plistURL, preferences: fixture.defaults) { _ in }

        XCTAssertThrowsError(try manager.setSyncInterval(1234))
        XCTAssertEqual(fixture.defaults.integer(forKey: LaunchdManager.syncIntervalPreferenceKey), 900)
        XCTAssertEqual(try Data(contentsOf: fixture.plistURL), original)
    }

    func testReloadFailureRestoresOldScheduleAndPreference() throws {
        let fixture = try makeFixture()
        let original = try Data(contentsOf: fixture.plistURL)
        var shouldFail = true
        let manager = LaunchdManager(plistURL: fixture.plistURL, preferences: fixture.defaults) { command in
            if shouldFail && command.first == "bootstrap" { shouldFail = false; throw LaunchdManagerError.launchctlFailed("injected") }
            if command.first == "bootstrap" { shouldFail = false }
        }

        XCTAssertThrowsError(try manager.setSyncInterval(3600))
        XCTAssertEqual(try Data(contentsOf: fixture.plistURL), original)
        XCTAssertEqual(fixture.defaults.integer(forKey: LaunchdManager.syncIntervalPreferenceKey), 900)
    }

    func testActiveSyncRejectsReloadWithoutChangingSavedState() throws {
        let fixture = try makeFixture()
        let original = try Data(contentsOf: fixture.plistURL)
        var commands: [[String]] = []
        let manager = LaunchdManager(plistURL: fixture.plistURL, preferences: fixture.defaults,
            commandRunner: { commands.append($0) }, runStateProvider: { (true, 123) })
        XCTAssertThrowsError(try manager.setSyncInterval(300))
        XCTAssertTrue(commands.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.plistURL), original)
        XCTAssertEqual(fixture.defaults.integer(forKey: LaunchdManager.syncIntervalPreferenceKey), 900)
    }

    func testUninstalledAgentSavesPreferenceWithoutLaunchctl() throws {
        let fixture = try makeFixture()
        try FileManager.default.removeItem(at: fixture.plistURL)
        var commands: [[String]] = []
        let manager = LaunchdManager(plistURL: fixture.plistURL, preferences: fixture.defaults) { commands.append($0) }
        try manager.setSyncInterval(600)
        XCTAssertTrue(commands.isEmpty)
        XCTAssertEqual(fixture.defaults.integer(forKey: LaunchdManager.syncIntervalPreferenceKey), 600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.plistURL.path))
    }

    func testStatusReportsInstalledIntervalInsteadOfPreference() throws {
        let fixture = try makeFixture()
        fixture.defaults.set(3600, forKey: LaunchdManager.syncIntervalPreferenceKey)
        let manager = LaunchdManager(plistURL: fixture.plistURL, preferences: fixture.defaults) { _ in }
        XCTAssertEqual(manager.status().intervalSeconds, 900)
    }

    private func makeFixture() throws -> (directory: URL, plistURL: URL, defaults: UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let plistURL = directory.appendingPathComponent("agent.plist")
        let plist: [String: Any] = ["Label": LaunchdManager.serviceLabel,
            "ProgramArguments": ["/tmp/calmirror", "sync"], "StartInterval": 900,
            "RunAtLoad": true]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
        let suite = "test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(900, forKey: LaunchdManager.syncIntervalPreferenceKey)
        return (directory, plistURL, defaults)
    }
}
