import Foundation

/// All filesystem locations in one place. Tests inject a temporary root.
public struct ClaunesPaths: Equatable {
    /// ~/Library/Application Support/waldo.Claunes
    public var supportDir: URL
    /// ~/Applications/Claunes
    public var applicationsDir: URL
    /// /Applications/Claude.app
    public var claudeApp: URL
    /// ~/Library/Application Support/Claude (the original, read-only for us)
    public var originalClaudeData: URL

    public init(supportDir: URL, applicationsDir: URL, claudeApp: URL, originalClaudeData: URL) {
        self.supportDir = supportDir
        self.applicationsDir = applicationsDir
        self.claudeApp = claudeApp
        self.originalClaudeData = originalClaudeData
    }

    public static var standard: ClaunesPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return ClaunesPaths(
            supportDir: appSupport.appendingPathComponent("waldo.Claunes", isDirectory: true),
            applicationsDir: home.appendingPathComponent("Applications/Claunes", isDirectory: true),
            claudeApp: URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true),
            originalClaudeData: appSupport.appendingPathComponent("Claude", isDirectory: true))
    }

    public var profilesFile: URL { supportDir.appendingPathComponent("profiles.json") }

    /// The --user-data-dir of a Claune.
    public func dataDir(for claune: Claune) -> URL {
        supportDir.appendingPathComponent(claune.id.uuidString.lowercased(), isDirectory: true)
    }

    public func appBundle(for claune: Claune) -> URL {
        applicationsDir.appendingPathComponent(claune.appFileName, isDirectory: true)
    }
}
