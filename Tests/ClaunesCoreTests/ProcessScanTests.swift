import XCTest
@testable import ClaunesCore

/// A rebuild must never touch a bundle with a live process in it (SPIKE.md, drift repair). This is the
/// kernel-side check behind that rule: processes whose executable lives under a directory, the caller included.
final class ProcessScanTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("claunes-scan-\(UUID().uuidString)/Fake.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }

    func testFindsProcessesExecutingUnderDirectoryIncludingSelf() throws {
        let sleeper = root.appendingPathComponent("sleeper")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: sleeper)
        let p = Process(); p.executableURL = sleeper; p.arguments = ["30"]
        try p.run()
        defer { p.terminate(); p.waitUntilExit() }
        let bundle = root.deletingLastPathComponent().deletingLastPathComponent()   // Fake.app
        XCTAssertTrue(ProcessScan.pids(executingUnder: bundle).contains(p.processIdentifier), "child running from inside the bundle")
        XCTAssertFalse(ProcessScan.pids(executingUnder: bundle).contains(getpid()), "the test runner is not inside the bundle")
        let ownDir = Bundle.main.executableURL!.resolvingSymlinksInPath().deletingLastPathComponent()
        XCTAssertTrue(ProcessScan.pids(executingUnder: ownDir).contains(getpid()), "the scan sees the calling process itself (the launcher case)")
        p.terminate(); p.waitUntilExit()
        XCTAssertFalse(ProcessScan.pids(executingUnder: bundle).contains(p.processIdentifier), "gone after exit")
    }
}
