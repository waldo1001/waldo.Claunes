import XCTest
@testable import ClaunesCore

/// Every Claude start rewrites the shared Claude in Chrome manifest to its own helper. A Claune must give it back
/// to the original Claude, and must never touch a manifest that does not point into a Claune (SPIKE.md, 2026-10-30).
final class NativeMessagingHostTests: XCTestCase {
    var root: URL!
    var claunesDir: URL!
    var claudeApp: URL!
    var manifest: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("claunes-nmh-\(UUID().uuidString)", isDirectory: true)
        claunesDir = root.appendingPathComponent("Applications/Claunes", isDirectory: true)
        claudeApp = root.appendingPathComponent("Claude.app", isDirectory: true)
        let helper = claudeApp.appendingPathComponent(NativeMessagingHost.helperPath)
        try fm.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        manifest = root.appendingPathComponent("Google/Chrome/NativeMessagingHosts/\(NativeMessagingHost.manifestName)")
        try fm.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    var realHelper: String { claudeApp.appendingPathComponent(NativeMessagingHost.helperPath).path }
    var clauneHelper: String { claunesDir.appendingPathComponent("Work.app/\(NativeMessagingHost.helperPath)").path }

    /// What Claude writes (A$r in app.asar): name, description, path, type, allowed_origins.
    func writeManifest(path: String) throws {
        let json: [String: Any] = ["name": "com.anthropic.claude_browser_extension",
                                   "description": "Claude Browser Extension Native Host", "path": path, "type": "stdio",
                                   "allowed_origins": ["chrome-extension://a/", "chrome-extension://b/"]]
        try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted).write(to: manifest)
    }

    func manifestPath() throws -> String? {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any]
        return json?["path"] as? String
    }

    func testRestorePointsAClauneManifestBackAtClaude() throws {
        try writeManifest(path: clauneHelper)
        XCTAssertTrue(NativeMessagingHost.restore(manifest: manifest, claunesDir: claunesDir, claudeApp: claudeApp))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        XCTAssertEqual(json["path"] as? String, realHelper)
        XCTAssertEqual(json["allowed_origins"] as? [String], ["chrome-extension://a/", "chrome-extension://b/"], "Claude's other keys stay")
        XCTAssertEqual(json["name"] as? String, "com.anthropic.claude_browser_extension")
        XCTAssertEqual(json["type"] as? String, "stdio")
    }

    func testRestoreLeavesManifestsOutsideClaunesAlone() throws {
        for path in [realHelper, "/Some/Other/Claude.app/\(NativeMessagingHost.helperPath)", claunesDir.path + "Elsewhere/x"] {
            try writeManifest(path: path)
            let before = try Data(contentsOf: manifest)
            XCTAssertFalse(NativeMessagingHost.restore(manifest: manifest, claunesDir: claunesDir, claudeApp: claudeApp), path)
            XCTAssertEqual(try Data(contentsOf: manifest), before, "not rewritten: \(path)")
        }
    }

    func testRestoreNeedsTheOriginalHelperAndAnExistingManifest() throws {
        XCTAssertFalse(NativeMessagingHost.restore(manifest: manifest, claunesDir: claunesDir, claudeApp: claudeApp))
        XCTAssertFalse(fm.fileExists(atPath: manifest.path), "a missing manifest is not created")
        try writeManifest(path: clauneHelper)
        try fm.removeItem(at: claudeApp.appendingPathComponent(NativeMessagingHost.helperPath))
        XCTAssertFalse(NativeMessagingHost.restore(manifest: manifest, claunesDir: claunesDir, claudeApp: claudeApp))
        XCTAssertEqual(try manifestPath(), clauneHelper, "no original helper: leave the Claune's (working) one")
    }

    func testManifestLocationsAreTheBrowsersClaudeWrites() {
        let support = URL(fileURLWithPath: "/U/Library/Application Support", isDirectory: true)
        let paths = NativeMessagingHost.manifests(appSupport: support).map(\.path)
        let name = NativeMessagingHost.manifestName
        XCTAssertEqual(paths, ["Google/Chrome", "Microsoft Edge", "PAB/Prisma Access Browser", "Island"]
            .map { "/U/Library/Application Support/\($0)/NativeMessagingHosts/\(name)" })
    }

    func testGuardRestoresWhileTheClauneRunsAndStopsWhenItExits() throws {
        let claune = Process(); claune.executableURL = URL(fileURLWithPath: "/bin/sleep"); claune.arguments = ["30"]
        try claune.run()
        defer { claune.terminate() }
        let finished = DispatchSemaphore(value: 0)
        let other = root.appendingPathComponent("Microsoft Edge/NativeMessagingHosts/\(NativeMessagingHost.manifestName)")
        DispatchQueue.global().async { [manifest, claunesDir, claudeApp] in
            NativeMessagingHost.guardManifests([other, manifest!], whileRunning: claune.processIdentifier,
                                               claunesDir: claunesDir!, claudeApp: claudeApp!, interval: 0.05)
            finished.signal()
        }
        for _ in 0..<2 {   // Claude rewrites at start and again whenever the extension changes
            try writeManifest(path: clauneHelper)
            let deadline = Date().addingTimeInterval(3)
            while try manifestPath() != realHelper, Date() < deadline { usleep(20_000) }
            XCTAssertEqual(try manifestPath(), realHelper)
        }
        XCTAssertEqual(finished.wait(timeout: .now()), .timedOut, "still guarding while the Claune runs")
        claune.terminate()
        XCTAssertEqual(finished.wait(timeout: .now() + 3), .success, "guard returns after the Claune exits")
    }

    func testGuardReturnsAtOnceForAProcessThatIsAlreadyGone() throws {
        let gone = Process(); gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try gone.run(); gone.waitUntilExit()
        let start = Date()
        NativeMessagingHost.guardManifests([manifest], whileRunning: gone.processIdentifier,
                                           claunesDir: claunesDir, claudeApp: claudeApp, interval: 10)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
