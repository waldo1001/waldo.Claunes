import Foundation

/// Compares a generated Claune bundle with the installed Claude Desktop and with the profile.
public enum DriftState: Equatable {
    /// Bundle is missing entirely.
    case missing
    /// Bundle exists but is not one of ours (no ClauneID) or its nested clone is gone.
    case corrupt(String)
    /// Generated from an older/newer Claude than the one installed, or older layout.
    case outdated(bundleVersion: String, installedVersion: String)
    /// Name/badge/color in the profile changed since generation.
    case profileChanged
    case upToDate

    public var needsRebuild: Bool { self != .upToDate }
    public var description: String {
        switch self {
        case .missing: return "App bundle missing"
        case .corrupt(let why): return "App bundle damaged: \(why)"
        case .outdated(let b, let i): return "Generated from Claude \(b), installed is \(i)"
        case .profileChanged: return "Name or icon changed"
        case .upToDate: return "Up to date"
        }
    }
}

public enum DriftDetector {
    public static func check(_ claune: Claune, paths: ClaunesPaths, installation: ClaudeInstallation) -> DriftState {
        let fm = FileManager.default
        let app = paths.appBundle(for: claune)
        guard fm.fileExists(atPath: app.path) else { return .missing }
        guard let stamp = BundleBuilder.stamp(of: app) else { return .corrupt("Info.plist is not ours") }
        guard stamp.id == claune.id else { return .corrupt("belongs to another Claune") }
        let nested = app.appendingPathComponent("Contents/\(BundleBuilder.nestedAppName)/Contents/MacOS/Claude")
        guard fm.fileExists(atPath: nested.path) else { return .corrupt("nested Claude.app missing") }
        let launcher = app.appendingPathComponent("Contents/MacOS/\(BundleBuilder.launcherExecutableName)")
        guard fm.isExecutableFile(atPath: launcher.path) else { return .corrupt("launcher missing") }
        if stamp.layoutVersion != BundleBuilder.layoutVersion
            || stamp.sourceVersion != installation.version
            || (installation.asarHash != nil && stamp.sourceAsarHash != installation.asarHash!) {
            return .outdated(bundleVersion: stamp.sourceVersion, installedVersion: installation.version)
        }
        if stamp.name != claune.name || stamp.dataDir != paths.dataDir(for: claune).path
            || stamp.bundleIdentifier != claune.bundleIdentifier {
            return .profileChanged
        }
        return .upToDate
    }
}
