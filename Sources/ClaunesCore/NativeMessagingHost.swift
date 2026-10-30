import Darwin
import Foundation

/// Keeps Claude in Chrome on the original Claude (see SPIKE.md, "Chrome native host", 2026-10-30).
/// At every start Claude writes `com.anthropic.claude_browser_extension.json` in each browser that has the extension,
/// with `path` = its own `Contents/Helpers/chrome-native-host`; a Claune would take the extension over until the real
/// Claude restarts. Claunes cannot pair with it anyway (relocated user data disables local pairing), so the manifest
/// always belongs to the original. Claude re-syncs only when a browser's Extensions folder changes, never when the
/// manifest does, so restoring it cannot loop; and only a manifest that points into a Claune is ever rewritten.
public enum NativeMessagingHost {
    public static let manifestName = "com.anthropic.claude_browser_extension.json"
    public static let helperPath = "Contents/Helpers/chrome-native-host"
    /// `ClauneLauncher --claune-native-host-guard <pid>`: the guard mode the launcher spawns just before it execs Claude.
    public static let guardArgument = "--claune-native-host-guard"

    /// The browsers Claude writes a manifest for (`PB()` in app.asar); the others it lists only get theirs removed.
    public static func manifests(appSupport: URL) -> [URL] {
        ["Google/Chrome", "Microsoft Edge", "PAB/Prisma Access Browser", "Island"].map {
            appSupport.appendingPathComponent("\($0)/NativeMessagingHosts/\(manifestName)")
        }
    }

    public static var standardManifests: [URL] {
        manifests(appSupport: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true))
    }

    /// Points `manifest` back at the original Claude's helper when it points into `claunesDir`. Keeps every other key.
    /// Returns true when it rewrote the file. Missing manifest, foreign path or no original helper: untouched.
    @discardableResult
    public static func restore(manifest: URL, claunesDir: URL, claudeApp: URL) -> Bool {
        let original = claudeApp.appendingPathComponent(helperPath)
        guard FileManager.default.fileExists(atPath: original.path),
              let data = try? Data(contentsOf: manifest),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let path = json["path"] as? String, isInside(path, claunesDir) else { return false }
        json["path"] = original.path
        guard let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes]) else { return false }
        return (try? out.write(to: manifest, options: .atomic)) != nil
    }

    static func isInside(_ path: String, _ dir: URL) -> Bool {
        let candidates = [dir.standardizedFileURL.path, dir.resolvingSymlinksInPath().path]
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return candidates.contains { p.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Restores `manifests` every `interval` until process `pid` (the Claune's Claude) exits; returns at once when it is
    /// already gone. Runs in the guard process the launcher spawns, so it lives exactly as long as the Claune.
    public static func guardManifests(_ manifests: [URL], whileRunning pid: pid_t, claunesDir: URL, claudeApp: URL,
                                      interval: TimeInterval = 1) {
        let done = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "be.waldo.claunes.native-host-guard")
        let exitSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        exitSource.setEventHandler { done.signal() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler {
            for m in manifests { restore(manifest: m, claunesDir: claunesDir, claudeApp: claudeApp) }
        }
        exitSource.resume()   // a pid that is already gone fires at once (libdispatch maps ESRCH to the exit event)
        timer.resume()
        done.wait()
        timer.cancel()
        exitSource.cancel()
    }
}
