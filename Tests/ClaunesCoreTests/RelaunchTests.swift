import XCTest
@testable import ClaunesCore

final class RelaunchTests: XCTestCase {
    func testMarkerIsStrippedAndReported() {
        let r = Relaunch.strip(["--claune-repaired", "--foo", "x"])
        XCTAssertEqual(r.args, ["--foo", "x"])
        XCTAssertTrue(r.repaired)
        let n = Relaunch.strip(["--foo"])
        XCTAssertEqual(n.args, ["--foo"])
        XCTAssertFalse(n.repaired)
    }

    func testWaitForExitReturnsWhenTheProcessIsGone() throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sleep"); p.arguments = ["30"]
        try p.run()
        XCTAssertFalse(ProcessScan.waitForExit(pid: p.processIdentifier, timeout: 0.2), "still running: times out")
        p.terminate()
        XCTAssertTrue(ProcessScan.waitForExit(pid: p.processIdentifier, timeout: 5), "exits once the process is gone")
    }
}

extension RelaunchTests {
    func testCliProbeDistinguishesOldAndNewCLI() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claunes-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let new = dir.appendingPathComponent("new"), old = dir.appendingPathComponent("old")
        try "#!/bin/sh\n[ \"$1\" = relaunch ] && [ \"$2\" = --probe ] && exit 0\nexit 2\n".write(to: new, atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho usage; exit 2\n".write(to: old, atomically: true, encoding: .utf8)
        for f in [new, old] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.path) }
        XCTAssertTrue(Relaunch.cliSupportsRelaunch(new))
        XCTAssertFalse(Relaunch.cliSupportsRelaunch(old))
        XCTAssertFalse(Relaunch.cliSupportsRelaunch(dir.appendingPathComponent("missing")))
    }

    func testSpawnDetachedRunsInItsOwnSession() throws {
        let pid = try XCTUnwrap(Relaunch.spawnDetached(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]))
        defer { kill(pid, SIGTERM) }
        XCTAssertEqual(kill(pid, 0), 0, "alive")
        XCTAssertNotEqual(getsid(pid), getsid(0), "own session: not torn down with the caller")
        XCTAssertNil(Relaunch.spawnDetached(URL(fileURLWithPath: "/nonexistent/binary"), arguments: []))
    }
}
