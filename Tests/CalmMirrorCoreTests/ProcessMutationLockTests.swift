import XCTest
@testable import CalmMirrorCore

final class ProcessMutationLockTests: XCTestCase {
    func testNonblockingAcquisitionReportsBusyAndLockReleases() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("mutation.lock")
        let first = try ProcessMutationLock.acquire(at: url, wait: true)
        XCTAssertThrowsError(try ProcessMutationLock.acquire(at: url, wait: false))
        first.release()
        XCTAssertNoThrow(try ProcessMutationLock.acquire(at: url, wait: false))
    }

    func testLockIsContendedAcrossProcesses() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mutation.lock")
        let lock = try ProcessMutationLock.acquire(at: url, wait: true)
        defer { lock.release() }

        let child = try runPython(
            "import fcntl, os, sys; fd=os.open(sys.argv[1], os.O_RDWR); " +
            "exec('try:\\n fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)\\nexcept BlockingIOError:\\n sys.exit(23)\\nelse:\\n sys.exit(0)')",
            argument: url.path
        )

        XCTAssertEqual(child.terminationStatus, 23, "The child should see the parent's exclusive lock as busy")
    }

    func testLockIsReleasedWhenOwningProcessExits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("mutation.lock")
        let ready = directory.appendingPathComponent("ready")
        let script = "import fcntl, os, sys, time; fd=os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o600); " +
            "fcntl.flock(fd, fcntl.LOCK_EX); open(sys.argv[2], 'w').close(); time.sleep(60)"
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", script, url.path, ready.path]
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }

        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path), "Child did not acquire the lock in time")
        XCTAssertThrowsError(try ProcessMutationLock.acquire(at: url, wait: false),
                             "The parent should see the child's lock while it is running")

        child.terminate()
        child.waitUntilExit()
        XCTAssertNoThrow(try ProcessMutationLock.acquire(at: url, wait: false),
                         "The kernel should release flock when the owning process exits")
    }

    private func runPython(_ script: String, argument: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, argument]
        try process.run()
        process.waitUntilExit()
        return process
    }
}
