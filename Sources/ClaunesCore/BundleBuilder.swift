import CryptoKit
import Foundation

/// Generates and refreshes the per-Claune app bundle (layout "R" from SPIKE.md, 2026-10-30):
///
///   <Name>.app/                           APFS clone of /Applications/Claude.app, then:
///   <Name>.app/Contents/Info.plist        Claude's, with our bundle id, display name, icon, launcher and Claune keys;
///                                         ElectronAsarIntegrity untouched (Electron checks a digest of it)
///   <Name>.app/Contents/MacOS/<exe>       claune-launcher (CFBundleExecutable), execs MacOS/Claude
///   <Name>.app/Contents/Resources/        + Claune.icns
///   everything re-signed inside-out with a local identity (CodeSigner)
public struct BundleBuilder {
    public static let layoutVersion = 2
    public static let launcherExecutableName = "ClauneLauncher"
    public static let iconFileName = "Claune.icns"

    public let paths: ClaunesPaths
    /// The claune-launcher binary to copy into the bundle.
    public let launcherBinary: URL
    /// `codesign --sign` identity for the whole bundle; "-" is ad-hoc (tests, Macs without a Developer ID).
    public let signingIdentity: String

    public init(paths: ClaunesPaths, launcherBinary: URL, signingIdentity: String = "-") {
        self.paths = paths
        self.launcherBinary = launcherBinary
        self.signingIdentity = signingIdentity
    }

    public enum BuildError: Error, LocalizedError {
        case launcherMissing(URL)
        case plistWrite(URL)
        case inUse(String, [pid_t])
        public var errorDescription: String? {
            switch self {
            case .launcherMissing(let u): return "Launcher binary not found at \(u.path)."
            case .plistWrite(let u): return "Could not write \(u.path)."
            case .inUse(let n, let p): return "\(n) is running (pid \(p.map(String.init).joined(separator: ", "))). Quit it first."
            }
        }
    }

    /// Creates or completely regenerates the bundle for `claune`. Returns the bundle URL.
    /// The applications directory is made writable for the duration and left read-only (see SPIKE.md, updater).
    @discardableResult
    public func build(_ claune: Claune, installation: ClaudeInstallation) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: launcherBinary.path) else {
            throw BuildError.launcherMissing(launcherBinary)
        }
        let app = paths.appBundle(for: claune)
        // Never rebuild a bundle with a live process in it (launcher, Claude or a helper): the swap below would move
        // the bundle they run from to the Trash. Checked by pid, not via LaunchServices, so the launcher's own pid counts.
        try refuseIfInUse(claune, app: app)
        return try FileOps.withWritable(paths.applicationsDir) {
            // Build in a temp dir next to the target, then swap, so a crash never leaves a half bundle.
            let tmp = paths.applicationsDir.appendingPathComponent(".building-\(claune.id.uuidString).app", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            try assemble(claune, installation: installation, at: tmp)
            // Re-check right before the swap: a launch may have happened while we were cloning.
            do { try refuseIfInUse(claune, app: app) } catch { try? FileManager.default.removeItem(at: tmp); throw error }
            if FileManager.default.fileExists(atPath: app.path) {
                try FileOps.trash(app)
            }
            try FileManager.default.moveItem(at: tmp, to: app)
            return app
        }
    }

    private func refuseIfInUse(_ claune: Claune, app: URL) throws {
        let live = ProcessScan.pids(executingUnder: app)
        if !live.isEmpty { throw BuildError.inUse(claune.name, live) }
    }

    private func assemble(_ claune: Claune, installation: ClaudeInstallation, at app: URL) throws {
        let fm = FileManager.default
        let contents = app.appendingPathComponent("Contents", isDirectory: true)

        // 1. Clone of Claude.app. Anthropic's provisioning profile and extended attributes go: our signature replaces theirs.
        try FileOps.clone(from: installation.bundleURL, to: app)
        try? fm.removeItem(at: contents.appendingPathComponent("embedded.provisionprofile"))
        try FileOps.clearExtendedAttributes(app)

        // 2. Launcher next to Claude; it becomes the bundle's main executable.
        try fm.copyItem(at: launcherBinary, to: contents.appendingPathComponent("MacOS/\(BundleBuilder.launcherExecutableName)"))

        // 3. Icon.
        try IconGenerator.writeICNS(badge: claune.badge, colorHex: claune.colorHex, baseIcon: installation.iconURL,
                                    to: contents.appendingPathComponent("Resources/\(BundleBuilder.iconFileName)"))

        // 4. Info.plist: Claude's, with our identity. CFBundleName stays "Claude" (Electron derives the helper app names
        //    from it) and ElectronAsarIntegrity stays byte-for-byte Claude's (its digest is baked into Electron).
        var plist = installation.infoPlist
        plist["CFBundleExecutable"] = BundleBuilder.launcherExecutableName
        plist["CFBundleDisplayName"] = claune.name
        plist["CFBundleIdentifier"] = claune.bundleIdentifier
        plist["CFBundleIconFile"] = BundleBuilder.iconFileName
        plist.removeValue(forKey: "CFBundleIconName")
        plist["ClauneID"] = claune.id.uuidString
        plist["ClauneName"] = claune.name
        plist["ClauneDataDir"] = paths.dataDir(for: claune).path
        plist["ClauneSourceVersion"] = installation.version
        plist["ClauneSourceAsarHash"] = installation.asarHash ?? ""
        plist["ClauneLayoutVersion"] = BundleBuilder.layoutVersion
        plist["ClauneLauncherHash"] = BundleBuilder.digest(of: launcherBinary) ?? ""
        plist["ClauneGeneratedAt"] = ISO8601DateFormatter().string(from: Date())
        let plistURL = contents.appendingPathComponent("Info.plist")
        guard (plist as NSDictionary).write(to: plistURL, atomically: true) else { throw BuildError.plistWrite(plistURL) }

        // 5. Seal it as the Claune (last: any change after this breaks the signature).
        try CodeSigner(identity: signingIdentity).signClone(app, original: installation.bundleURL, identifier: claune.bundleIdentifier)

        try fm.createDirectory(at: paths.dataDir(for: claune), withIntermediateDirectories: true)
    }

    /// SHA-256 of a file, used to detect a stale launcher inside a Claune after a redeploy.
    public static func digest(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the Claune-specific keys of a generated bundle's Info.plist.
    public static func stamp(of bundle: URL) -> BundleStamp? {
        guard let d = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let idString = d["ClauneID"] as? String, let id = UUID(uuidString: idString) else { return nil }
        return BundleStamp(id: id, name: d["ClauneName"] as? String ?? "", dataDir: d["ClauneDataDir"] as? String ?? "",
                           sourceVersion: d["ClauneSourceVersion"] as? String ?? "", sourceAsarHash: d["ClauneSourceAsarHash"] as? String ?? "",
                           layoutVersion: d["ClauneLayoutVersion"] as? Int ?? 0, bundleIdentifier: d["CFBundleIdentifier"] as? String ?? "",
                           launcherHash: d["ClauneLauncherHash"] as? String ?? "")
    }
}

public struct BundleStamp: Equatable {
    public var id: UUID
    public var name: String
    public var dataDir: String
    public var sourceVersion: String
    public var sourceAsarHash: String
    public var layoutVersion: Int
    public var bundleIdentifier: String
    public var launcherHash: String
}
