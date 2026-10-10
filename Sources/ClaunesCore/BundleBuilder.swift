import CryptoKit
import Foundation

/// Generates and refreshes the per-Claune app bundle (layout "G" from SPIKE.md):
///
///   <Name>.app/Contents/Info.plist        ours
///   <Name>.app/Contents/MacOS/<exe>       claune-launcher
///   <Name>.app/Contents/MacOS/Claude  ->  ../Claude.app/Contents/MacOS/Claude
///   <Name>.app/Contents/Frameworks    ->  ../Claude.app/Contents/Frameworks
///   <Name>.app/Contents/Resources/        Claune.icns + symlink per entry of the nested Resources
///   <Name>.app/Contents/Claude.app/       pristine APFS clone of /Applications/Claude.app
public struct BundleBuilder {
    public static let layoutVersion = 1
    public static let launcherExecutableName = "ClauneLauncher"
    public static let nestedAppName = "Claude.app"
    public static let iconFileName = "Claune.icns"

    public let paths: ClaunesPaths
    /// The claune-launcher binary to copy into the bundle.
    public let launcherBinary: URL

    public init(paths: ClaunesPaths, launcherBinary: URL) {
        self.paths = paths
        self.launcherBinary = launcherBinary
    }

    public enum BuildError: Error, LocalizedError {
        case launcherMissing(URL)
        case plistWrite(URL)
        public var errorDescription: String? {
            switch self {
            case .launcherMissing(let u): return "Launcher binary not found at \(u.path)."
            case .plistWrite(let u): return "Could not write \(u.path)."
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
        return try FileOps.withWritable(paths.applicationsDir) {
            // Build in a temp dir next to the target, then swap, so a crash never leaves a half bundle.
            let tmp = paths.applicationsDir.appendingPathComponent(".building-\(claune.id.uuidString).app", isDirectory: true)
            try? FileManager.default.removeItem(at: tmp)
            try assemble(claune, installation: installation, at: tmp)
            if FileManager.default.fileExists(atPath: app.path) {
                try FileOps.trash(app)
            }
            try FileManager.default.moveItem(at: tmp, to: app)
            return app
        }
    }

    private func assemble(_ claune: Claune, installation: ClaudeInstallation, at app: URL) throws {
        let fm = FileManager.default
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        // 1. Pristine clone of Claude.app. Never modified afterwards.
        let nested = contents.appendingPathComponent(BundleBuilder.nestedAppName, isDirectory: true)
        try FileOps.clone(from: installation.bundleURL, to: nested)

        // 2. Launcher + symlinks. The copy is re-signed ad-hoc: a release build ships it Developer ID signed, and that
        //    signature on the main executable of our unsealed wrapper makes Gatekeeper call the Claune "damaged".
        let launcherCopy = macos.appendingPathComponent(BundleBuilder.launcherExecutableName)
        try fm.copyItem(at: launcherBinary, to: launcherCopy)
        try FileOps.adHocSign(launcherCopy)
        try FileOps.symlink(at: macos.appendingPathComponent("Claude"), to: "../\(BundleBuilder.nestedAppName)/Contents/MacOS/Claude")
        try FileOps.symlink(at: contents.appendingPathComponent("Frameworks"), to: "../\(BundleBuilder.nestedAppName)/Contents/Frameworks")
        let nestedResources = nested.appendingPathComponent("Contents/Resources", isDirectory: true)
        for entry in try fm.contentsOfDirectory(atPath: nestedResources.path) {
            try FileOps.symlink(at: resources.appendingPathComponent(entry), to: "../\(BundleBuilder.nestedAppName)/Contents/Resources/\(entry)")
        }
        if let pkg = try? Data(contentsOf: installation.bundleURL.appendingPathComponent("Contents/PkgInfo")) {
            try pkg.write(to: contents.appendingPathComponent("PkgInfo"))
        }

        // 3. Icon.
        try IconGenerator.writeICNS(badge: claune.badge, colorHex: claune.colorHex, to: resources.appendingPathComponent(BundleBuilder.iconFileName))

        // 4. Info.plist: Claude's, with our identity.
        var plist = installation.infoPlist
        plist["CFBundleExecutable"] = BundleBuilder.launcherExecutableName
        plist["CFBundleName"] = claune.name
        plist["CFBundleDisplayName"] = claune.name
        plist["CFBundleIdentifier"] = claune.bundleIdentifier
        plist["CFBundleIconFile"] = BundleBuilder.iconFileName
        plist.removeValue(forKey: "CFBundleIconName")
        plist.removeValue(forKey: "LSEnvironment") // not needed; keeps the plist honest
        if var integrity = installation.asarIntegrity, let asar = integrity["Resources/app.asar"] {
            // Electron looks the hash up by the asar path relative to our Contents (see SPIKE.md).
            integrity["\(BundleBuilder.nestedAppName)/Contents/Resources/app.asar"] = asar
            plist["ElectronAsarIntegrity"] = integrity
        }
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
