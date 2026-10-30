import Foundation

/// Small filesystem helpers used by the bundle builder and migration.
public enum FileOps {
    /// APFS clone of a file or directory tree (instant, shares blocks). Falls back to a copy on other filesystems.
    public static func clone(from src: URL, to dst: URL) throws {
        let rc = clonefile(src.path, dst.path, 0)
        if rc == 0 { return }
        let err = errno
        // ENOTSUP / EXDEV: not APFS or cross-volume -> regular copy.
        if err == ENOTSUP || err == EXDEV {
            try FileManager.default.copyItem(at: src, to: dst)
            return
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(err),
                      userInfo: [NSLocalizedDescriptionKey: "clonefile(\(src.path) -> \(dst.path)) failed: \(String(cString: strerror(err)))"])
    }

    public static func chmod(_ url: URL, mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    /// Runs `body` with `dir` writable (0755) and restores 0555 afterwards.
    public static func withWritable<T>(_ dir: URL, _ body: () throws -> T) throws -> T {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try chmod(dir, mode: 0o755)
        defer { try? chmod(dir, mode: 0o555) }
        return try body()
    }

    /// Total size in bytes of a directory tree (follows nothing, counts the files once).
    public static func folderSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else { return 0 }
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// `xattr -cr`: a clone carries com.apple.provenance and similar attributes, which a strict signature check rejects.
    public static func clearExtendedAttributes(_ url: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-cr", url.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
    }

    /// Moves to the Trash. Never deletes.
    public static func trash(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
