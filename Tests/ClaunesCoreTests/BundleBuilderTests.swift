import XCTest
@testable import ClaunesCore

/// Builds against a FAKE Claude.app (a minimal bundle with the same shape), never the real one.
final class BundleBuilderTests: XCTestCase {
    var root: URL!
    var paths: ClaunesPaths!
    var launcher: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("claunes-tests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        paths = ClaunesPaths(supportDir: root.appendingPathComponent("support"), applicationsDir: root.appendingPathComponent("apps"),
                             claudeApp: root.appendingPathComponent("Claude.app"), originalClaudeData: root.appendingPathComponent("orig"))
        // fake Claude.app
        let c = paths.claudeApp.appendingPathComponent("Contents")
        try fm.createDirectory(at: c.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: c.appendingPathComponent("Frameworks/Electron Framework.framework"), withIntermediateDirectories: true)
        try fm.createDirectory(at: c.appendingPathComponent("Resources/en.lproj"), withIntermediateDirectories: true)
        try "fake".write(to: c.appendingPathComponent("MacOS/Claude"), atomically: true, encoding: .utf8)
        try "asar".write(to: c.appendingPathComponent("Resources/app.asar"), atomically: true, encoding: .utf8)
        try "APPL????".write(to: c.appendingPathComponent("PkgInfo"), atomically: true, encoding: .utf8)
        let plist: [String: Any] = ["CFBundleIdentifier": ClaudeInstallation.bundleIdentifier, "CFBundleShortVersionString": "1.0.0",
                                    "CFBundleExecutable": "Claude", "CFBundleName": "Claude", "CFBundleIconName": "Claude", "CFBundleIconFile": "electron.icns",
                                    "ElectronAsarIntegrity": ["Resources/app.asar": ["algorithm": "SHA256", "hash": "abc"]],
                                    "LSEnvironment": ["MallocNanoZone": "0"]]
        (plist as NSDictionary).write(to: c.appendingPathComponent("Info.plist"), atomically: true)
        launcher = root.appendingPathComponent("launcher")
        try "#!/bin/sh\necho launcher\n".write(to: launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
    }

    override func tearDownWithError() throws {
        try? FileOps.chmod(paths.applicationsDir, mode: 0o755)
        try? FileManager.default.removeItem(at: root)
    }

    func testLocateRejectsMissingAndForeignBundles() throws {
        XCTAssertThrowsError(try ClaudeInstallation.locate(at: root.appendingPathComponent("Nope.app")))
        let foreign = root.appendingPathComponent("Other.app/Contents")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        (["CFBundleIdentifier": "x.y"] as NSDictionary).write(to: foreign.appendingPathComponent("Info.plist"), atomically: true)
        XCTAssertThrowsError(try ClaudeInstallation.locate(at: root.appendingPathComponent("Other.app")))
        let inst = try ClaudeInstallation.locate(paths: paths)
        XCTAssertEqual(inst.version, "1.0.0")
        XCTAssertEqual(inst.asarHash, "abc")
    }

    func testBuildProducesLayoutG() throws {
        let fm = FileManager.default
        let inst = try ClaudeInstallation.locate(paths: paths)
        let claune = Claune(name: "Test-Work", colorHex: "#2E7D32")
        let app = try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst)
        XCTAssertEqual(app.lastPathComponent, "Test-Work.app")
        let c = app.appendingPathComponent("Contents")
        XCTAssertTrue(fm.fileExists(atPath: c.appendingPathComponent("Claude.app/Contents/MacOS/Claude").path), "nested pristine clone")
        XCTAssertTrue(fm.isExecutableFile(atPath: c.appendingPathComponent("MacOS/ClauneLauncher").path))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: c.appendingPathComponent("MacOS/Claude").path), "../Claude.app/Contents/MacOS/Claude")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: c.appendingPathComponent("Frameworks").path), "../Claude.app/Contents/Frameworks")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: c.appendingPathComponent("Resources/app.asar").path), "../Claude.app/Contents/Resources/app.asar")
        XCTAssertTrue(fm.fileExists(atPath: c.appendingPathComponent("Resources/Claune.icns").path))
        let plist = NSDictionary(contentsOf: c.appendingPathComponent("Info.plist")) as! [String: Any]
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, claune.bundleIdentifier)
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "ClauneLauncher")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Test-Work")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "Claune.icns")
        XCTAssertNil(plist["CFBundleIconName"])
        let integrity = plist["ElectronAsarIntegrity"] as! [String: Any]
        XCTAssertNotNil(integrity["Resources/app.asar"])
        XCTAssertEqual((integrity["Claude.app/Contents/Resources/app.asar"] as? [String: Any])?["hash"] as? String, "abc")
        XCTAssertEqual(plist["ClauneID"] as? String, claune.id.uuidString)
        XCTAssertEqual(plist["ClauneDataDir"] as? String, paths.dataDir(for: claune).path)
        XCTAssertTrue(fm.fileExists(atPath: paths.dataDir(for: claune).path))
        // the nested clone is untouched
        let nestedPlist = NSDictionary(contentsOf: c.appendingPathComponent("Claude.app/Contents/Info.plist")) as! [String: Any]
        XCTAssertEqual(nestedPlist["CFBundleIdentifier"] as? String, ClaudeInstallation.bundleIdentifier)
        // applications dir left read-only (updater guard)
        let perms = try fm.attributesOfItem(atPath: paths.applicationsDir.path)[.posixPermissions] as! Int
        XCTAssertEqual(perms & 0o777, 0o555)
        // drift
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst), .upToDate)
    }

    func testDriftStates() throws {
        let fm = FileManager.default
        var inst = try ClaudeInstallation.locate(paths: paths)
        let claune = Claune(name: "Test-Drift", colorHex: "#2E7D32")
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst), .missing)
        try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst)
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst), .upToDate)
        // Claude got updated
        let plistURL = paths.claudeApp.appendingPathComponent("Contents/Info.plist")
        var p = NSDictionary(contentsOf: plistURL) as! [String: Any]
        p["CFBundleShortVersionString"] = "2.0.0"
        (p as NSDictionary).write(to: plistURL, atomically: true)
        inst = try ClaudeInstallation.locate(paths: paths)
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst), .outdated(bundleVersion: "1.0.0", installedVersion: "2.0.0"))
        // rebuild fixes it and trashes nothing outside the apps dir
        try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst)
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst), .upToDate)
        // renamed profile
        var renamed = claune; renamed.name = "Test-Drift2"
        XCTAssertEqual(DriftDetector.check(renamed, paths: paths, installation: inst), .missing)
        // corrupt: nested clone removed
        try FileOps.withWritable(paths.applicationsDir) {
            try fm.removeItem(at: paths.appBundle(for: claune).appendingPathComponent("Contents/Claude.app"))
        }
        if case .corrupt = DriftDetector.check(claune, paths: paths, installation: inst) {} else { XCTFail("expected corrupt") }
    }

    func testLauncherDriftIsDetected() throws {
        let inst = try ClaudeInstallation.locate(paths: paths)
        let claune = Claune(name: "Test-Launcher", colorHex: "#2E7D32")
        try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst)
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst, launcherBinary: launcher), .upToDate)
        let newer = root.appendingPathComponent("launcher2")
        try "#!/bin/sh\necho launcher v2\n".write(to: newer, atomically: true, encoding: .utf8)
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst, launcherBinary: newer), .launcherOutdated)
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst, launcherBinary: nil), .upToDate, "nil skips the comparison")
        let stamp = try XCTUnwrap(BundleBuilder.stamp(of: paths.appBundle(for: claune)))
        XCTAssertEqual(stamp.launcherHash, BundleBuilder.digest(of: launcher))
    }

    /// `codesign -dv` output (it writes to stderr) for a file.
    private func signatureInfo(of file: URL) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); p.arguments = ["-dv", file.path]
        let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// A release build ships a Developer ID + hardened-runtime launcher. Copied as-is into a wrapper that has no
    /// bundle seal, Gatekeeper reports the Claune as "damaged" (code has no resources but signature indicates they
    /// must be present). The copy inside the bundle must therefore always be ad-hoc signed (SPIKE.md, code signing summary).
    func testBuiltLauncherIsAdHocSignedWhateverTheSourceSignature() throws {
        let fm = FileManager.default
        let signedSource = root.appendingPathComponent("signed-launcher")
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: signedSource)   // any Mach-O with a real (non-adhoc) signature
        XCTAssertTrue(signatureInfo(of: signedSource).contains("Signature size="), "fixture must carry a real signature")
        let inst = try ClaudeInstallation.locate(paths: paths)
        let claune = Claune(name: "Test-Sign", colorHex: "#2E7D32")
        let app = try BundleBuilder(paths: paths, launcherBinary: signedSource).build(claune, installation: inst)
        let copy = app.appendingPathComponent("Contents/MacOS/ClauneLauncher")
        let info = signatureInfo(of: copy)
        XCTAssertTrue(info.contains("Signature=adhoc"), "launcher inside the Claune must be ad-hoc signed, got:\n\(info)")
        XCTAssertTrue(info.contains("TeamIdentifier=not set"), info)
        // The source is untouched and the drift stamp still hashes the shipped launcher, not the re-signed copy.
        XCTAssertTrue(signatureInfo(of: signedSource).contains("Signature size="), "source launcher must not be modified")
        XCTAssertEqual(BundleBuilder.stamp(of: app)?.launcherHash, BundleBuilder.digest(of: signedSource))
        XCTAssertNotEqual(BundleBuilder.digest(of: copy), BundleBuilder.digest(of: signedSource), "re-signing changes the bytes of the copy")
    }

    func testMigrationCopiesAndRefusesNonEmptyTarget() throws {
        let fm = FileManager.default
        XCTAssertNil(Migration.detectOriginalData(paths: paths))
        let orig = paths.originalClaudeData
        try fm.createDirectory(at: orig.appendingPathComponent("Local Storage"), withIntermediateDirectories: true)
        try "{}".write(to: orig.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: orig.appendingPathComponent("claude_desktop_config.json"), atomically: true, encoding: .utf8)
        let cand = try XCTUnwrap(Migration.detectOriginalData(paths: paths))
        XCTAssertTrue(cand.hasConfig)
        let claune = Claune(name: "Test-Mig", colorHex: "#000000")
        try Migration.importOriginalData(into: claune, paths: paths)
        XCTAssertTrue(fm.fileExists(atPath: paths.dataDir(for: claune).appendingPathComponent("claude_desktop_config.json").path))
        XCTAssertTrue(fm.fileExists(atPath: orig.appendingPathComponent("config.json").path), "original untouched")
        XCTAssertThrowsError(try Migration.importOriginalData(into: claune, paths: paths))
    }

    func testIconGeneratorDrawsTileInColor() throws {
        let img = IconGenerator.tile(badge: "W", colorHex: "#2E7D32", pixels: 64)
        let rep = NSBitmapImageRep(data: try IconGenerator.pngData(img))!
        let corner = rep.colorAt(x: 1, y: 1)!
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.01, "corners transparent")
        XCTAssertEqual(rep.pixelsWide, 64, "exact pixel size regardless of screen scale")
        let top = rep.colorAt(x: 32, y: 9)!.usingColorSpace(.sRGB)!   // inside the tile, above the letter
        XCTAssertGreaterThan(top.greenComponent, 0.4, "tile is painted in the profile color")
        XCTAssertLessThan(top.redComponent, 0.3)
        XCTAssertLessThan(top.blueComponent, 0.3)
    }
}
