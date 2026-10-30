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
        try fm.createDirectory(at: c.appendingPathComponent("Resources/en.lproj"), withIntermediateDirectories: true)
        // Real Mach-O files, signed like Claude's: main binary with a restricted entitlement, a helper app, a native addon.
        let mainBinary = root.appendingPathComponent("Claude-binary")   // signed outside the bundle, then moved in
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: mainBinary)
        try sign(mainBinary, entitlements: ["com.apple.security.cs.allow-jit": true, "keychain-access-groups": ["Q6L2SF6YDW.x"],
                                            "com.apple.developer.team-identifier": "Q6L2SF6YDW"])
        try fm.moveItem(at: mainBinary, to: c.appendingPathComponent("MacOS/Claude"))
        let helper = c.appendingPathComponent("Frameworks/Claude Helper.app/Contents")
        try fm.createDirectory(at: helper.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: helper.appendingPathComponent("MacOS/Claude Helper"))
        (["CFBundleIdentifier": "com.anthropic.claudefordesktop.helper", "CFBundleExecutable": "Claude Helper", "CFBundlePackageType": "APPL"] as NSDictionary)
            .write(to: helper.appendingPathComponent("Info.plist"), atomically: true)
        try sign(helper.deletingLastPathComponent(), entitlements: ["com.apple.security.cs.allow-jit": true])
        let addon = c.appendingPathComponent("Resources/app.asar.unpacked/native.node")
        try fm.createDirectory(at: addon.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: addon)
        try "provision".write(to: c.appendingPathComponent("embedded.provisionprofile"), atomically: true, encoding: .utf8)
        try "asar".write(to: c.appendingPathComponent("Resources/app.asar"), atomically: true, encoding: .utf8)
        try "APPL????".write(to: c.appendingPathComponent("PkgInfo"), atomically: true, encoding: .utf8)
        let plist: [String: Any] = ["CFBundleIdentifier": ClaudeInstallation.bundleIdentifier, "CFBundleShortVersionString": "1.0.0",
                                    "CFBundleExecutable": "Claude", "CFBundleName": "Claude", "CFBundleIconName": "Claude", "CFBundleIconFile": "electron.icns",
                                    "ElectronAsarIntegrity": ["Resources/app.asar": ["algorithm": "SHA256", "hash": "abc"],
                                                              "Resources/ion-dist.asar": ["algorithm": "SHA256", "hash": "def"]],
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

    func testBuildProducesLayoutR() throws {
        let fm = FileManager.default
        let inst = try ClaudeInstallation.locate(paths: paths)
        let claune = Claune(name: "Test-Work", colorHex: "#2E7D32")
        let app = try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst)
        XCTAssertEqual(app.lastPathComponent, "Test-Work.app")
        let c = app.appendingPathComponent("Contents")
        // A flat clone: real files, no nested Claude.app, no symlinks into one.
        XCTAssertFalse(fm.fileExists(atPath: c.appendingPathComponent("Claude.app").path), "no nested clone in layout R")
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: c.appendingPathComponent("MacOS/Claude").path), "MacOS/Claude is the real binary")
        XCTAssertTrue(fm.isExecutableFile(atPath: c.appendingPathComponent("MacOS/Claude").path))
        XCTAssertTrue(fm.isExecutableFile(atPath: c.appendingPathComponent("MacOS/ClauneLauncher").path))
        XCTAssertTrue(fm.fileExists(atPath: c.appendingPathComponent("Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper").path))
        XCTAssertTrue(fm.fileExists(atPath: c.appendingPathComponent("Resources/Claune.icns").path))
        XCTAssertFalse(fm.fileExists(atPath: c.appendingPathComponent("embedded.provisionprofile").path), "Anthropic's profile does not match our signature")
        let plist = NSDictionary(contentsOf: c.appendingPathComponent("Info.plist")) as! [String: Any]
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, claune.bundleIdentifier)
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "ClauneLauncher")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Test-Work")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Claude", "Electron derives the helper app names from CFBundleName")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "Claune.icns")
        XCTAssertNil(plist["CFBundleIconName"])
        // Electron checks a digest of the whole dictionary: it must be Claude's, byte for byte (SPIKE.md, 2026-10-30).
        XCTAssertEqual(plist["ElectronAsarIntegrity"] as? NSDictionary, inst.asarIntegrity.map { $0 as NSDictionary })
        XCTAssertEqual(plist["ClauneID"] as? String, claune.id.uuidString)
        XCTAssertEqual(plist["ClauneDataDir"] as? String, paths.dataDir(for: claune).path)
        XCTAssertEqual(plist["ClauneLayoutVersion"] as? Int, 2)
        XCTAssertTrue(fm.fileExists(atPath: paths.dataDir(for: claune).path))
        // Sealed and signed as the Claune.
        XCTAssertEqual(codesign(["--verify", "--deep", "--strict", app.path]).status, 0, codesign(["--verify", "--deep", "--strict", app.path]).output)
        XCTAssertTrue(codesign(["-dv", app.path]).output.contains("Identifier=\(claune.bundleIdentifier)"))
        // The installed Claude is untouched.
        let source = NSDictionary(contentsOf: paths.claudeApp.appendingPathComponent("Contents/Info.plist")) as! [String: Any]
        XCTAssertEqual(source["CFBundleIdentifier"] as? String, ClaudeInstallation.bundleIdentifier)
        XCTAssertTrue(fm.fileExists(atPath: paths.claudeApp.appendingPathComponent("Contents/embedded.provisionprofile").path))
        // applications dir left read-only (updater guard)
        let perms = try fm.attributesOfItem(atPath: paths.applicationsDir.path)[.posixPermissions] as! Int
        XCTAssertEqual(perms & 0o777, 0o555)
        XCTAssertEqual(DriftDetector.check(claune, paths: paths, installation: inst), .upToDate)
    }

    /// Every Mach-O is re-signed with our identity, keeping its own entitlements minus the restricted ones that need
    /// Anthropic's provisioning profile (with them the process would be killed at exec).
    func testEveryComponentIsResignedWithoutRestrictedEntitlements() throws {
        let inst = try ClaudeInstallation.locate(paths: paths)
        let claune = Claune(name: "Test-Ents", colorHex: "#2E7D32")
        let app = try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst)
        let c = app.appendingPathComponent("Contents")
        let main = c.appendingPathComponent("MacOS/Claude")
        let mainEnts = entitlements(of: main)
        XCTAssertEqual(mainEnts["com.apple.security.cs.allow-jit"] as? Bool, true)
        XCTAssertNil(mainEnts["keychain-access-groups"])
        XCTAssertNil(mainEnts["com.apple.developer.team-identifier"])
        XCTAssertTrue(codesign(["-dv", main.path]).output.contains("Identifier=\(claune.bundleIdentifier)"),
                      "Claude runs as the Claune: stable designated requirement for keychain and TCC")
        let helper = c.appendingPathComponent("Frameworks/Claude Helper.app")
        XCTAssertEqual(entitlements(of: helper)["com.apple.security.cs.allow-jit"] as? Bool, true)
        XCTAssertTrue(codesign(["-dv", helper.path]).output.contains("Identifier=com.anthropic.claudefordesktop.helper"), "helper identifiers are kept")
        for file in [main, helper, c.appendingPathComponent("Resources/app.asar.unpacked/native.node")] {
            let info = codesign(["-dv", file.path]).output
            XCTAssertTrue(info.contains("Signature=adhoc"), "\(file.lastPathComponent) must carry our (test: ad-hoc) signature:\n\(info)")
            XCTAssertTrue(info.contains("runtime"), "\(file.lastPathComponent) needs the hardened runtime:\n\(info)")
        }
    }

    func testPreferredIdentityIsTheDeveloperIDApplicationCertificate() {
        let out = """
          1) 1111111111111111111111111111111111111111 "Apple Development: Someone (AAAAAAAAAA)"
          2) 2222222222222222222222222222222222222222 "Developer ID Application: Dynex (92A2K3Q7NH)"
             2 valid identities found
        """
        XCTAssertEqual(CodeSigner.developerIDIdentity(inFindIdentityOutput: out), "2222222222222222222222222222222222222222")
        XCTAssertNil(CodeSigner.developerIDIdentity(inFindIdentityOutput: "     0 valid identities found\n"))
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
        // corrupt: Claude binary removed
        try FileOps.withWritable(paths.applicationsDir) {
            try fm.removeItem(at: paths.appBundle(for: claune).appendingPathComponent("Contents/MacOS/Claude"))
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

    /// Runs codesign, returns exit status and combined output (codesign -d writes to stderr).
    private func codesign(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); p.arguments = args
        let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private func sign(_ url: URL, entitlements: [String: Any]) throws {
        let ents = root.appendingPathComponent("ents-\(UUID().uuidString).plist")
        (entitlements as NSDictionary).write(to: ents, atomically: true)
        let r = codesign(["--force", "--sign", "-", "--entitlements", ents.path, url.path])
        guard r.status == 0 else { throw NSError(domain: "test", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.output]) }
    }

    private func entitlements(of url: URL) -> [String: Any] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-d", "--entitlements", "-", "--xml", url.path]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
    }

    /// `codesign -dv` output (it writes to stderr) for a file.
    private func signatureInfo(of file: URL) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); p.arguments = ["-dv", file.path]
        let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// A release build ships a Developer ID signed launcher. Inside a Claune it is the bundle's main executable and must
    /// carry the Claune's own signature (here ad-hoc, the builder's identity in tests), never the one it was shipped with.
    func testBuiltLauncherCarriesTheClauneSignatureWhateverTheSourceSignature() throws {
        let fm = FileManager.default
        let signedSource = root.appendingPathComponent("signed-launcher")
        try fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: signedSource)   // any Mach-O with a real (non-adhoc) signature
        XCTAssertTrue(signatureInfo(of: signedSource).contains("Signature size="), "fixture must carry a real signature")
        let inst = try ClaudeInstallation.locate(paths: paths)
        let claune = Claune(name: "Test-Sign", colorHex: "#2E7D32")
        let app = try BundleBuilder(paths: paths, launcherBinary: signedSource).build(claune, installation: inst)
        let copy = app.appendingPathComponent("Contents/MacOS/ClauneLauncher")
        let info = signatureInfo(of: copy)
        XCTAssertTrue(info.contains("Signature=adhoc"), "launcher inside the Claune must carry the builder's signature, got:\n\(info)")
        XCTAssertTrue(info.contains("Identifier=\(claune.bundleIdentifier)"), info)
        XCTAssertTrue(info.contains("TeamIdentifier=not set"), info)
        // The source is untouched and the drift stamp still hashes the shipped launcher, not the re-signed copy.
        XCTAssertTrue(signatureInfo(of: signedSource).contains("Signature size="), "source launcher must not be modified")
        XCTAssertEqual(BundleBuilder.stamp(of: app)?.launcherHash, BundleBuilder.digest(of: signedSource))
        XCTAssertNotEqual(BundleBuilder.digest(of: copy), BundleBuilder.digest(of: signedSource), "re-signing changes the bytes of the copy")
    }

    /// Regression for the 2026-10-10 incident: the launcher rebuilt the bundle it was itself running from, which
    /// moved a live app bundle to the Trash. build() must refuse while ANY process executes from the bundle,
    /// the Claune's own launcher included, and must leave the bundle untouched.
    func testBuildRefusesWhileAProcessRunsFromTheBundle() throws {
        let fm = FileManager.default
        let inst = try ClaudeInstallation.locate(paths: paths)
        let claune = Claune(name: "Test-Live", colorHex: "#2E7D32")
        let app = try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst)
        let before = try XCTUnwrap(BundleBuilder.stamp(of: app))
        // A process executing from inside the bundle, like the launcher or Claude itself.
        let resident = app.appendingPathComponent("Contents/MacOS/resident")
        try fm.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: resident)
        let p = Process(); p.executableURL = resident; p.arguments = ["30"]
        try p.run()
        defer { if p.isRunning { p.terminate(); p.waitUntilExit() } }
        XCTAssertThrowsError(try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst)) { error in
            guard case BundleBuilder.BuildError.inUse(let name, let pids) = error else { return XCTFail("expected inUse, got \(error)") }
            XCTAssertEqual(name, "Test-Live")
            XCTAssertTrue(pids.contains(p.processIdentifier))
        }
        XCTAssertTrue(fm.fileExists(atPath: resident.path), "bundle must not have been moved or trashed")
        XCTAssertEqual(BundleBuilder.stamp(of: app), before, "bundle must be untouched")
        XCTAssertFalse(fm.fileExists(atPath: paths.applicationsDir.appendingPathComponent(".building-\(claune.id.uuidString).app").path), "no half-built bundle left behind")
        p.terminate(); p.waitUntilExit()
        XCTAssertNoThrow(try BundleBuilder(paths: paths, launcherBinary: launcher).build(claune, installation: inst), "rebuild works once the process is gone")
    }

    /// Drift is repaired by the app/CLI BEFORE a launch, never by the launcher of the running Claune.
    func testRepairIfNeededRebuildsOnlyWhenDrifted() throws {
        let manager = try ClauneManager(paths: paths, launcherBinary: launcher)
        let claune = try manager.create(name: "Test-Repair")
        XCTAssertFalse(try manager.repairIfNeeded(claune), "fresh bundle: nothing to do")
        let plistURL = paths.claudeApp.appendingPathComponent("Contents/Info.plist")
        var p = NSDictionary(contentsOf: plistURL) as! [String: Any]
        p["CFBundleShortVersionString"] = "2.0.0"
        (p as NSDictionary).write(to: plistURL, atomically: true)
        XCTAssertEqual(manager.drift(claune).needsRebuild, true)
        XCTAssertTrue(try manager.repairIfNeeded(claune), "outdated: rebuilt")
        XCTAssertEqual(manager.drift(claune), .upToDate)
        XCTAssertEqual(manager.store.claune(id: claune.id)?.generatedFromVersion, "2.0.0")
    }

    /// Rename and delete also move a bundle; they must refuse while a process runs from it (kernel view, not only LS).
    func testUpdateAndDeleteRefuseWhileAProcessRunsFromTheBundle() throws {
        let manager = try ClauneManager(paths: paths, launcherBinary: launcher)
        let claune = try manager.create(name: "Test-Busy")
        let app = paths.appBundle(for: claune)
        let resident = app.appendingPathComponent("Contents/MacOS/resident")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: resident)
        let p = Process(); p.executableURL = resident; p.arguments = ["30"]
        try p.run()
        defer { if p.isRunning { p.terminate(); p.waitUntilExit() } }
        var renamed = claune; renamed.name = "Test-Busy2"
        XCTAssertThrowsError(try manager.update(renamed))
        XCTAssertThrowsError(try manager.delete(claune))
        XCTAssertFalse(try manager.repairIfNeeded(claune), "running: not repaired, not an error")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resident.path), "bundle still in place")
        XCTAssertNotNil(manager.store.claune(id: claune.id), "profile kept")
        p.terminate(); p.waitUntilExit()
        XCTAssertNoThrow(try manager.delete(claune))
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

    /// Gives the fake Claude.app an icon: a solid blue tile (stands in for Claude's real icon).
    private func installFakeClaudeIcon() throws -> URL {
        let url = paths.claudeApp.appendingPathComponent("Contents/Resources/electron.icns")
        try IconGenerator.writeICNS(badge: " ", colorHex: "#0000FF", to: url)
        return url
    }

    private func srgb(_ rep: NSBitmapImageRep, _ fx: CGFloat, _ fy: CGFloat) -> NSColor {
        rep.colorAt(x: Int(fx * CGFloat(rep.pixelsWide)), y: Int(fy * CGFloat(rep.pixelsHigh)))!.usingColorSpace(.sRGB)!
    }

    func testInstallationExposesClaudeIconOnlyWhenPresent() throws {
        XCTAssertNil(try ClaudeInstallation.locate(paths: paths).iconURL, "no icon file in the fake app yet")
        let icon = try installFakeClaudeIcon()
        XCTAssertEqual(try ClaudeInstallation.locate(paths: paths).iconURL?.path, icon.path)
    }

    func testIconIsClaudeIconUnmodifiedWithCornerBadge() throws {
        let base = NSImage(contentsOf: try installFakeClaudeIcon())!
        let rep = NSBitmapImageRep(data: try IconGenerator.pngData(IconGenerator.icon(badge: "W", colorHex: "#2E7D32", pixels: 128, base: base)))!
        XCTAssertEqual(rep.pixelsWide, 128)
        let topLeft = srgb(rep, 0.25, 0.25)   // colorAt is top-left origin
        XCTAssertGreaterThan(topLeft.blueComponent, 0.8, "Claude's icon is drawn as-is")
        XCTAssertLessThan(topLeft.greenComponent, 0.2)
        let badge = srgb(rep, 0.74, 0.74)      // bottom-right corner badge, off the letter
        let ring = srgb(rep, 0.74, 0.60)
        XCTAssertTrue(badge.greenComponent > 0.4 || ring.greenComponent > 0.4, "corner badge in the profile color")
        XCTAssertLessThan(min(badge.blueComponent, ring.blueComponent), 0.3)
    }

    /// macOS 26 boxes an icon in a gray tile when anything is drawn outside the icon shape, so the badge
    /// must stay inside Claude's tile (1024 canvas, 822 tile, 100 px margin, like the real electron.icns).
    func testBadgeStaysInsideClaudeIconShape() throws {
        let base = IconGenerator.tile(badge: " ", colorHex: "#0000FF", pixels: 256, inset: 100.0 / 1024)
        let baseRep = NSBitmapImageRep(data: try IconGenerator.pngData(base))!
        let rep = NSBitmapImageRep(data: try IconGenerator.pngData(IconGenerator.icon(badge: "IF", colorHex: "#2E7D32", pixels: 256, base: base)))!
        var outside = 0
        for y in 0..<256 { for x in 0..<256 where baseRep.colorAt(x: x, y: y)!.alphaComponent < 0.02 {
            if rep.colorAt(x: x, y: y)!.alphaComponent > 0.1 { outside += 1 }
        } }
        XCTAssertEqual(outside, 0, "pixels painted outside Claude's icon shape")
    }

    func testIconFallsBackToTileWithoutClaudeIcon() throws {
        let rep = NSBitmapImageRep(data: try IconGenerator.pngData(IconGenerator.icon(badge: "W", colorHex: "#2E7D32", pixels: 64, base: nil)))!
        let top = srgb(rep, 0.5, 0.15)
        XCTAssertGreaterThan(top.greenComponent, 0.4)
        XCTAssertLessThan(top.blueComponent, 0.3)
    }

    func testBuiltClauneIconUsesInstalledClaudeIcon() throws {
        _ = try installFakeClaudeIcon()
        let inst = try ClaudeInstallation.locate(paths: paths)
        let app = try BundleBuilder(paths: paths, launcherBinary: launcher).build(Claune(name: "Test-Icon", colorHex: "#2E7D32"), installation: inst)
        let icns = NSImage(contentsOf: app.appendingPathComponent("Contents/Resources/Claune.icns"))!
        let rep = NSBitmapImageRep(data: try IconGenerator.pngData(icns))!
        XCTAssertGreaterThan(srgb(rep, 0.25, 0.25).blueComponent, 0.8)
    }
}
