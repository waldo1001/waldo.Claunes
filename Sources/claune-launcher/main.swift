// claune-launcher: lives at <Claune>.app/Contents/MacOS/ClauneLauncher.
// It resolves the Claune's data dir, then execs the real Claude binary THROUGH the symlink inside this
// bundle (that keeps the Dock identity ours, see SPIKE.md) with --user-data-dir. Exactly one exec, from a
// bundle that does not move: this process IS a process of the Claune, so it never rebuilds the bundle it
// runs from (the 2026-10-10 incident in SPIKE.md). Drift is repaired by waldo.Claunes before a launch, or
// handed to the installed CLI, which waits for this pid to exit, rebuilds and launches the fresh bundle.
import AppKit
import ClaunesCore
import Foundation

func alert(_ title: String, _ message: String, openDownload: Bool = false) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.alertStyle = .critical
    a.addButton(withTitle: "Quit")
    if openDownload { a.addButton(withTitle: "Download Claude") }
    app.activate(ignoringOtherApps: true)
    if a.runModal() == .alertSecondButtonReturn, openDownload {
        NSWorkspace.shared.open(ClaudeInstallation.downloadURL)
    }
    exit(1)
}

let bundle = Bundle.main.bundleURL
let contents = bundle.appendingPathComponent("Contents")
let plist = (NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any]) ?? [:]
guard let idString = plist["ClauneID"] as? String, let clauneID = UUID(uuidString: idString) else {
    alert("Not a Claune", "This app bundle has no Claune identity. Open waldo.Claunes and resync it.")
}

let paths = ClaunesPaths.standard
var dataDir = URL(fileURLWithPath: plist["ClauneDataDir"] as? String ?? paths.supportDir.appendingPathComponent(idString.lowercased()).path, isDirectory: true)
var claune: Claune? = nil
if let store = try? ProfileStore(paths: paths), let c = store.claune(id: clauneID) {
    claune = c
    dataDir = paths.dataDir(for: c)
}

// Arguments LaunchServices passed us (Dock, Spotlight, `open`, or the CLI after a repair).
let (forwardedArgs, repaired) = Relaunch.strip(Array(CommandLine.arguments.dropFirst()))

/// The installed waldo.Claunes app, if any.
func installedApp() -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "be.waldo.claunes") }
/// The launcher that app ships (drift comparison) and its CLI (repair hand-off).
func installedAppLauncher() -> URL? {
    guard let url = installedApp()?.appendingPathComponent("Contents/MacOS/claune-launcher"),
          FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
    return url
}
func installedCLI() -> URL? {
    guard let url = installedApp()?.appendingPathComponent("Contents/MacOS/claunes"),
          FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
    return url
}

// Drift hand-off. Never a rebuild from here: that moved the live bundle to the Trash and left this pid
// attributed to a bundle in the Trash (see SPIKE.md). `repaired` breaks the loop when the CLI relaunched us.
if !repaired, let c = claune, let installation = try? ClaudeInstallation.locate(paths: paths) {
    let state = DriftDetector.check(c, paths: paths, installation: installation, launcherBinary: installedAppLauncher())
    let drifted: Bool = { if case .outdated = state { return true }; return state == .launcherOutdated }()
    if drifted, let cli = installedCLI(), Relaunch.cliSupportsRelaunch(cli),
       Relaunch.spawnDetached(cli, arguments: ["relaunch", c.id.uuidString, "--after-pid", String(getpid())]) != nil {
        exit(0)   // the CLI waits for this pid, rebuilds, and launches the fresh bundle with the marker
    }
    // No installed app (or an older one): run the clone we have. It is complete and works, just older.
}

let target = contents.appendingPathComponent("MacOS/Claude").path   // symlink into the nested clone
guard FileManager.default.fileExists(atPath: target) else {
    if (try? ClaudeInstallation.locate(paths: paths)) == nil {
        alert("Claude Desktop is not installed", "waldo.Claunes runs the Claude Desktop app from /Applications/Claude.app. Install it, then resync this Claune.", openDownload: true)
    }
    alert("Claune is damaged", "The embedded copy of Claude is missing. Open waldo.Claunes and use Resync.")
}

try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

// First launch of a fresh Claune: explain the browser sign-in trap once (see SPIKE.md).
if !FileManager.default.fileExists(atPath: dataDir.appendingPathComponent("Cookies").path) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let a = NSAlert()
    a.messageText = "Signing in to \(claune?.name ?? "this Claune")"
    a.informativeText = "Claude signs in through your web browser. If the browser is already logged in to another Claude account, that account will land in this Claune.\n\nFor a different account: sign out of claude.ai in the browser first, or use a private window. Keep this Claune in front when you click Sign in, so the sign-in callback is routed here."
    a.alertStyle = .informational
    a.addButton(withTitle: "Continue")
    a.addButton(withTitle: "Sign out of claude.ai in browser first")
    app.activate(ignoringOtherApps: true)
    if a.runModal() == .alertSecondButtonReturn {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/logout")!)
    }
}
var args: [String] = [target, "--user-data-dir=\(dataDir.path)"]
args.append(contentsOf: forwardedArgs)
let cargs = args.map { strdup($0) } + [nil]
execv(target, cargs)
alert("Could not start Claude", "execv failed: \(String(cString: strerror(errno)))")
