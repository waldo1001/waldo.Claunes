import Foundation

/// First-run import of the existing Claude Desktop data into a Claune. Copy only; the original is never touched.
public enum Migration {
    public struct Candidate: Equatable {
        public var url: URL
        public var sizeBytes: Int64
        public var hasConfig: Bool
    }

    /// Returns the original data folder if it looks like a used Claude Desktop profile.
    public static func detectOriginalData(paths: ClaunesPaths) -> Candidate? {
        let fm = FileManager.default
        let url = paths.originalClaudeData
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let markers = ["config.json", "Local Storage", "IndexedDB", "Cookies", "claude_desktop_config.json"]
        let present = markers.filter { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
        guard present.count >= 2 else { return nil }
        return Candidate(url: url, sizeBytes: FileOps.folderSize(url),
                         hasConfig: fm.fileExists(atPath: url.appendingPathComponent("claude_desktop_config.json").path))
    }

    public enum MigrationError: Error, LocalizedError {
        case targetNotEmpty(URL)
        public var errorDescription: String? {
            switch self {
            case .targetNotEmpty(let u): return "The Claune's data folder \(u.path) already contains data."
            }
        }
    }

    /// Copies (APFS clone when possible) the original data into the Claune's data dir.
    /// Refuses if the target already has content. Does not require Claude to be quit, but the
    /// caller should warn that a running original may still be writing (databases may be mid-write).
    public static func importOriginalData(into claune: Claune, paths: ClaunesPaths) throws {
        let fm = FileManager.default
        let target = paths.dataDir(for: claune)
        if fm.fileExists(atPath: target.path) {
            let entries = (try? fm.contentsOfDirectory(atPath: target.path)) ?? []
            guard entries.isEmpty else { throw MigrationError.targetNotEmpty(target) }
            try fm.removeItem(at: target)
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileOps.clone(from: paths.originalClaudeData, to: target)
    }
}
