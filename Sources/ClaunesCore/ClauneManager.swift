import Foundation

public enum ClauneManagerError: Error, LocalizedError {
    case running(String)
    public var errorDescription: String? {
        switch self { case .running(let n): return "\(n) is running. Quit it first." }
    }
}

/// High-level operations the UI and CLI call. Owns a ProfileStore and a BundleBuilder.
public final class ClauneManager {
    public let paths: ClaunesPaths
    public let store: ProfileStore
    public let launcherBinary: URL

    public init(paths: ClaunesPaths, launcherBinary: URL) throws {
        self.paths = paths
        self.store = try ProfileStore(paths: paths)
        self.launcherBinary = launcherBinary
    }

    public func installation() throws -> ClaudeInstallation { try ClaudeInstallation.locate(paths: paths) }

    public var builder: BundleBuilder { BundleBuilder(paths: paths, launcherBinary: launcherBinary) }

    /// Create the profile and its app bundle.
    @discardableResult
    public func create(name: String, colorHex: String? = nil, badge: String? = nil) throws -> Claune {
        let installation = try installation()
        var claune = try store.add(name: name, colorHex: colorHex, badge: badge)
        try builder.build(claune, installation: installation)
        claune.generatedFromVersion = installation.version
        try store.update(claune)
        return claune
    }

    /// Rename / recolor / rebadge, then regenerate the bundle (new name => new bundle folder name).
    public func update(_ updated: Claune) throws {
        guard let old = store.claune(id: updated.id) else { throw ProfileStoreError.notFound(updated.id) }
        guard !Runtime.isRunning(old) else { throw ClauneManagerError.running(old.name) }
        let installation = try installation()
        if old.appFileName != updated.appFileName {
            let oldApp = paths.appBundle(for: old)
            try FileOps.withWritable(paths.applicationsDir) { try FileOps.trash(oldApp) }
        }
        var c = updated
        try builder.build(c, installation: installation)
        c.generatedFromVersion = installation.version
        try store.update(c)
    }

    /// Regenerate the bundle from the currently installed Claude ("Resync").
    public func resync(_ claune: Claune) throws {
        guard !Runtime.isRunning(claune) else { throw ClauneManagerError.running(claune.name) }
        let installation = try installation()
        var c = claune
        try builder.build(c, installation: installation)
        c.generatedFromVersion = installation.version
        try store.update(c)
    }

    public func drift(_ claune: Claune) -> DriftState {
        guard let installation = try? installation() else { return .corrupt("Claude Desktop not installed") }
        return DriftDetector.check(claune, paths: paths, installation: installation, launcherBinary: launcherBinary)
    }

    /// Moves app bundle and data folder to the Trash and forgets the profile. Never hard-deletes.
    public func delete(_ claune: Claune) throws {
        guard !Runtime.isRunning(claune) else { throw ClauneManagerError.running(claune.name) }
        try FileOps.withWritable(paths.applicationsDir) { try FileOps.trash(paths.appBundle(for: claune)) }
        try FileOps.trash(paths.dataDir(for: claune))
        try store.remove(id: claune.id)
    }

    public func dataFolderSize(_ claune: Claune) -> Int64 { FileOps.folderSize(paths.dataDir(for: claune)) }

    public func mcpConfigURL(_ claune: Claune) -> URL { paths.dataDir(for: claune).appendingPathComponent("claude_desktop_config.json") }

    /// Creates an empty MCP config if none exists yet, so "Edit MCP config" always has a file to open.
    public func ensureMCPConfig(_ claune: Claune) throws -> URL {
        let url = mcpConfigURL(claune)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "{\n  \"mcpServers\": {}\n}\n".write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }
}
