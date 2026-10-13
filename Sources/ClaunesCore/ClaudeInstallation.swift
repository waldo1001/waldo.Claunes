import Foundation

/// Facts about the installed Claude Desktop. Read-only.
public struct ClaudeInstallation: Equatable {
    public static let downloadURL = URL(string: "https://claude.ai/download")!
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"

    public let bundleURL: URL
    public let version: String
    /// The ElectronAsarIntegrity dictionary from Info.plist, keyed "Resources/app.asar".
    public let asarIntegrity: [String: Any]?
    public let infoPlist: [String: Any]

    public static func == (a: ClaudeInstallation, b: ClaudeInstallation) -> Bool {
        a.bundleURL == b.bundleURL && a.version == b.version
    }

    public enum Problem: Error, LocalizedError, Equatable {
        case notInstalled(URL)
        case unreadable(URL)
        case notClaude(URL, String)

        public var errorDescription: String? {
            switch self {
            case .notInstalled(let u): return "Claude Desktop is not installed at \(u.path). Download it from \(ClaudeInstallation.downloadURL.absoluteString)."
            case .unreadable(let u): return "Could not read \(u.path)/Contents/Info.plist."
            case .notClaude(let u, let id): return "\(u.path) is not Claude Desktop (bundle id \(id))."
            }
        }
    }

    public static func locate(at url: URL) throws -> ClaudeInstallation {
        let fm = FileManager.default
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard fm.fileExists(atPath: url.path) else { throw Problem.notInstalled(url) }
        guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any] else { throw Problem.unreadable(url) }
        let id = dict["CFBundleIdentifier"] as? String ?? ""
        guard id == bundleIdentifier else { throw Problem.notClaude(url, id) }
        let version = dict["CFBundleShortVersionString"] as? String ?? "?"
        return ClaudeInstallation(bundleURL: url, version: version,
                                  asarIntegrity: dict["ElectronAsarIntegrity"] as? [String: Any], infoPlist: dict)
    }

    public static func locate(paths: ClaunesPaths) throws -> ClaudeInstallation {
        try locate(at: paths.claudeApp)
    }

    /// Claude's own app icon (CFBundleIconFile in Contents/Resources), if present. Used, unmodified, under the Claune badge.
    public var iconURL: URL? {
        guard var name = infoPlist["CFBundleIconFile"] as? String, !name.isEmpty else { return nil }
        if (name as NSString).pathExtension.isEmpty { name += ".icns" }
        let url = bundleURL.appendingPathComponent("Contents/Resources/\(name)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Hash of app.asar as recorded by Electron, used for drift detection.
    public var asarHash: String? {
        (asarIntegrity?["Resources/app.asar"] as? [String: Any])?["hash"] as? String
    }
}
