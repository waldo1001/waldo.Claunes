// claune-launcher: lives at <Claune>.app/Contents/MacOS/ClauneLauncher.
// It resolves the Claune's data dir, repairs version drift when safe, then execs the real
// Claude binary THROUGH the symlink inside this bundle (that keeps the Dock identity ours,
// see SPIKE.md) with --user-data-dir.
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

// Drift repair: if Claude Desktop was updated since this bundle was generated, regenerate it
// (an APFS clone, well under a second) before starting. Safe because we are the only process
// of this Claune right now (we have not exec'd yet) and the launcher binary itself is kept.
if let c = claune, let installation = try? ClaudeInstallation.locate(paths: paths) {
    let state = DriftDetector.check(c, paths: paths, installation: installation)
    if case .outdated = state {
        let launcherCopy = contents.appendingPathComponent("MacOS/\(BundleBuilder.launcherExecutableName)")
        // Copy ourselves aside first: build() trashes the old bundle, including this file.
        let tmpLauncher = FileManager.default.temporaryDirectory.appendingPathComponent("claune-launcher-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: launcherCopy, to: tmpLauncher)
            try BundleBuilder(paths: paths, launcherBinary: tmpLauncher).build(c, installation: installation)
            try? FileManager.default.removeItem(at: tmpLauncher)
            // Exec the freshly generated launcher (same path, new file). Not via LaunchServices:
            // LS already considers this bundle id running (that is us) and would only activate it.
            let fresh = launcherCopy.path
            let cargs = ([fresh] + CommandLine.arguments.dropFirst()).map { strdup($0) } + [nil]
            execv(fresh, cargs)
            FileHandle.standardError.write("claune-launcher: exec of regenerated launcher failed: \(String(cString: strerror(errno)))\n".data(using: .utf8)!)
        } catch {
            // Fall through and run the old clone; the main app offers Resync.
            FileHandle.standardError.write("claune-launcher: resync failed: \(error)\n".data(using: .utf8)!)
        }
    }
}

let target = contents.appendingPathComponent("MacOS/Claude").path   // symlink into the nested clone
guard FileManager.default.fileExists(atPath: target) else {
    if (try? ClaudeInstallation.locate(paths: paths)) == nil {
        alert("Claude Desktop is not installed", "waldo.Claunes runs the Claude Desktop app from /Applications/Claude.app. Install it, then resync this Claune.", openDownload: true)
    }
    alert("Claune is damaged", "The embedded copy of Claude is missing. Open waldo.Claunes and use Resync.")
}

try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
var args: [String] = [target, "--user-data-dir=\(dataDir.path)"]
args.append(contentsOf: CommandLine.arguments.dropFirst())
let cargs = args.map { strdup($0) } + [nil]
execv(target, cargs)
alert("Could not start Claude", "execv failed: \(String(cString: strerror(errno)))")
