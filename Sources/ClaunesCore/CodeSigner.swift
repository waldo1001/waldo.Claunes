import Foundation

/// Re-signs a clone of Claude.app as a Claune (layout R, SPIKE.md 2026-10-30): every Mach-O, inside-out, with the
/// hardened runtime and each component's own entitlements minus the restricted ones that only work with Anthropic's
/// provisioning profile. With a Developer ID the designated requirement (identifier + team) survives every re-sign,
/// so a keychain "Always Allow" survives Claude updates; ad-hoc ("-") works too but prompts again after each rebuild.
public struct CodeSigner {
    /// "-" for ad-hoc, otherwise a certificate SHA-1 or name as `codesign --sign` accepts it.
    public let identity: String

    public init(identity: String) { self.identity = identity }

    /// Entitlements that need a matching provisioning profile; signed without one, the process is killed at exec.
    static let restrictedEntitlementPrefixes = ["com.apple.application-identifier", "com.apple.developer.", "keychain-access-groups"]

    public enum SignError: Error, LocalizedError {
        case codesign(String, String)
        public var errorDescription: String? {
            switch self { case .codesign(let what, let msg): return "codesign of \(what) failed: \(msg)" }
        }
    }

    /// The first "Developer ID Application" identity in the keychain, else ad-hoc.
    public static func preferredIdentity() -> String {
        let r = run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])
        return developerIDIdentity(inFindIdentityOutput: r.output) ?? "-"
    }

    /// Parses `security find-identity -v -p codesigning`; returns the SHA-1 of the Developer ID Application identity.
    public static func developerIDIdentity(inFindIdentityOutput output: String) -> String? {
        for line in output.split(separator: "\n") where line.contains("\"Developer ID Application:") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count > 1, fields[1].count == 40 { return String(fields[1]) }
        }
        return nil
    }

    /// Signs `bundle`, a clone of `original`. Nested code keeps its identifier; the bundle and the other executables in
    /// its Contents/MacOS (Claude next to our launcher) get `identifier`, so Claude runs with the Claune's identity.
    public func signClone(_ bundle: URL, original: URL, identifier: String) throws {
        let contents = bundle.appendingPathComponent("Contents")
        let macos = contents.appendingPathComponent("MacOS")
        let main = (NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist"))?["CFBundleExecutable"] as? String) ?? ""
        let fm = FileManager.default
        var looseCode: [URL] = []
        var bundles: [URL] = []
        guard let walker = fm.enumerator(at: contents, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for case let url as URL in walker {
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if v.isSymbolicLink == true { continue }
            if v.isDirectory == true {
                if CodeSigner.isCodeBundle(url) { bundles.append(url) }
            } else if v.isRegularFile == true, url.deletingLastPathComponent().standardizedFileURL != macos.standardizedFileURL,
                      !CodeSigner.isBundleMainBinary(url), CodeSigner.isMachO(url) {
                looseCode.append(url)
            }
        }
        // Deepest first, so every container is signed after the code it seals.
        let deepestFirst: (URL, URL) -> Bool = { $0.pathComponents.count > $1.pathComponents.count }
        for url in looseCode.sorted(by: deepestFirst) + bundles.sorted(by: deepestFirst) {
            try sign(url, entitlementsFrom: counterpart(of: url, in: bundle, original: original), identifier: nil)
        }
        for name in (try fm.contentsOfDirectory(atPath: macos.path)).sorted() where name != main {
            let url = macos.appendingPathComponent(name)
            try sign(url, entitlementsFrom: counterpart(of: url, in: bundle, original: original), identifier: identifier)
        }
        try sign(bundle, entitlementsFrom: nil, identifier: identifier)
    }

    private func counterpart(of url: URL, in bundle: URL, original: URL) -> URL {
        let rel = url.standardizedFileURL.path.dropFirst(bundle.standardizedFileURL.path.count)
        return URL(fileURLWithPath: original.standardizedFileURL.path + rel)
    }

    private func sign(_ url: URL, entitlementsFrom source: URL?, identifier: String?) throws {
        var args = ["--force", "--sign", identity, "--options", "runtime", "--timestamp=none"]
        args += identifier.map { ["--identifier", $0] } ?? ["--preserve-metadata=identifier"]
        var entsFile: URL? = nil
        if let source, let ents = CodeSigner.entitlements(of: source) {
            let kept = ents.filter { key, _ in !CodeSigner.restrictedEntitlementPrefixes.contains { key.hasPrefix($0) } }
            if !kept.isEmpty {
                let f = FileManager.default.temporaryDirectory.appendingPathComponent("claune-ents-\(UUID().uuidString).plist")
                guard (kept as NSDictionary).write(to: f, atomically: true) else { throw SignError.codesign(url.lastPathComponent, "cannot write entitlements") }
                entsFile = f
                args += ["--entitlements", f.path]
            }
        }
        defer { if let f = entsFile { try? FileManager.default.removeItem(at: f) } }
        let r = CodeSigner.run("/usr/bin/codesign", args + [url.path])
        guard r.status == 0 else {
            let msg = r.output.split(separator: "\n").filter { !$0.hasSuffix("replacing existing signature") }.joined(separator: "\n")
            throw SignError.codesign(url.lastPathComponent, msg)
        }
    }

    static func entitlements(of url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let r = run("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", url.path], stdoutOnly: true)
        guard r.status == 0, let data = r.output.data(using: .utf8), !data.isEmpty else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// An .app or .framework directory with an Info.plist (an empty placeholder is not code).
    static func isCodeBundle(_ url: URL) -> Bool {
        let fm = FileManager.default
        switch url.pathExtension {
        case "app": return fm.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path)
        case "framework": return fm.fileExists(atPath: url.appendingPathComponent("Resources/Info.plist").path)
        default: return false
        }
    }

    /// The main binary of a nested bundle is signed with the bundle, not on its own.
    static func isBundleMainBinary(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "MacOS", parent.deletingLastPathComponent().lastPathComponent == "Contents",
           parent.deletingLastPathComponent().deletingLastPathComponent().pathExtension == "app" { return true }
        let versions = parent.deletingLastPathComponent()
        if versions.lastPathComponent == "Versions", versions.deletingLastPathComponent().pathExtension == "framework",
           url.lastPathComponent == versions.deletingLastPathComponent().deletingPathExtension().lastPathComponent { return true }
        return false
    }

    static func isMachO(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4), d.count == 4 else { return false }
        let magic = d.withUnsafeBytes { $0.load(as: UInt32.self) }
        return [0xFEEDFACF, 0xCFFAEDFE, 0xFEEDFACE, 0xCEFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(magic)
    }

    static func run(_ tool: String, _ args: [String], stdoutOnly: Bool = false) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = stdoutOnly ? FileHandle.nullDevice : out
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
