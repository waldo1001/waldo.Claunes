// claunes: command line interface for smoke tests and scripting.
import AppKit
import ClaunesCore
import Foundation

func usage() -> Never {
    print("""
    usage: claunes <command> [args]
      list                         show all Claunes, running state, drift
      create <name> [#hex] [badge] create a Claune and its app bundle
      launch <name>                launch or activate
      resync <name|--all>          regenerate bundle(s) from the installed Claude
      rename <name> <new name>
      delete <name>                move app + data to the Trash (asks for confirmation)
      migrate <name>               import ~/Library/Application Support/Claude into <name>
      doctor                       check the installation and paths
      handler [bundle-id]          show or set the claude:// handler
      icon <out.icns> [badge] [#hex] write a generated icon (used by the build script)
      trash-previous-install <app>  move an older waldo.Claunes.app to the Trash (deploy script)
    """)
    exit(2)
}

func launcherURL() -> URL {
    // Next to this executable in a SwiftPM build, or inside the app bundle.
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    let candidates = [exe.appendingPathComponent("claune-launcher"),
                      Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/claune-launcher")]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } ?? candidates[0]
}

func fail(_ msg: String) -> Never { FileHandle.standardError.write("error: \(msg)\n".data(using: .utf8)!); exit(1) }

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }
let paths = ClaunesPaths.standard
let manager: ClauneManager
do { manager = try ClauneManager(paths: paths, launcherBinary: launcherURL()) } catch { fail("\(error)") }

func find(_ name: String) -> Claune {
    guard let c = manager.store.claunes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { fail("no Claune named \(name)") }
    return c
}

do {
    switch cmd {
    case "list":
        if manager.store.claunes.isEmpty { print("no Claunes yet") }
        for c in manager.store.claunes {
            let running = Runtime.isRunning(c) ? "running" : "stopped"
            let size = ByteCountFormatter.string(fromByteCount: manager.dataFolderSize(c), countStyle: .file)
            print("\(c.badge)  \(c.name)  \(c.colorHex)  \(running)  \(size)  \(manager.drift(c).description)")
            print("     app:  \(paths.appBundle(for: c).path)")
            print("     data: \(paths.dataDir(for: c).path)")
        }
    case "create":
        guard args.count >= 2 else { usage() }
        let c = try manager.create(name: args[1], colorHex: args.count > 2 ? args[2] : nil, badge: args.count > 3 ? args[3] : nil)
        print("created \(c.name) -> \(paths.appBundle(for: c).path)")
    case "launch":
        guard args.count == 2 else { usage() }
        let c = find(args[1])
        let sem = DispatchSemaphore(value: 0)
        var failure: Error?
        Task { do { try await Runtime.launchOrActivate(c, paths: paths) } catch { failure = error }; sem.signal() }
        sem.wait()
        if let f = failure { fail("\(f)") }
        print("launched \(c.name)")
    case "resync":
        guard args.count == 2 else { usage() }
        let targets = args[1] == "--all" ? manager.store.claunes : [find(args[1])]
        for c in targets {
            if Runtime.isRunning(c) { print("skipped \(c.name): running (repaired automatically at its next launch)"); continue }
            try manager.resync(c); print("resynced \(c.name)")
        }
    case "rename":
        guard args.count == 3 else { usage() }
        var c = find(args[1]); c.name = args[2]; c.badge = Claune.defaultBadge(for: args[2])
        try manager.update(c); print("renamed")
    case "delete":
        guard args.count == 2 else { usage() }
        let c = find(args[1])
        print("Move \(c.name) (app + data) to the Trash? [y/N] ", terminator: "")
        guard readLine()?.lowercased() == "y" else { print("cancelled"); exit(0) }
        if Runtime.isRunning(c) { fail("\(c.name) is running; quit it first") }
        try manager.delete(c); print("moved to Trash")
    case "migrate":
        guard args.count == 2 else { usage() }
        let c = find(args[1])
        guard let cand = Migration.detectOriginalData(paths: paths) else { fail("no existing Claude data found at \(paths.originalClaudeData.path)") }
        print("importing \(ByteCountFormatter.string(fromByteCount: cand.sizeBytes, countStyle: .file)) from \(cand.url.path) (copy; original untouched)")
        try Migration.importOriginalData(into: c, paths: paths); print("done")
    case "doctor":
        print("support dir:  \(paths.supportDir.path)")
        print("apps dir:     \(paths.applicationsDir.path)")
        print("launcher:     \(launcherURL().path) \(FileManager.default.isExecutableFile(atPath: launcherURL().path) ? "ok" : "MISSING")")
        do { let i = try manager.installation(); print("Claude:       \(i.bundleURL.path) version \(i.version) asar \(i.asarHash ?? "-")") } catch { print("Claude:       \(error.localizedDescription)") }
        if let m = Migration.detectOriginalData(paths: paths) { print("original data: \(m.url.path) \(ByteCountFormatter.string(fromByteCount: m.sizeBytes, countStyle: .file))") } else { print("original data: none") }
        print("claude:// handler: \(ProtocolHandler.current ?? "none")")
    case "icon":
        guard args.count >= 2 else { usage() }
        try IconGenerator.writeICNS(badge: args.count > 2 ? args[2] : "C", colorHex: args.count > 3 ? args[3] : Claune.palette[0], to: URL(fileURLWithPath: args[1]))
        print("wrote \(args[1])")
    case "trash-previous-install":
        guard args.count == 2 else { usage() }
        let app = URL(fileURLWithPath: args[1])
        let id = (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleIdentifier"] as? String
        guard id == "be.waldo.claunes" else { fail("\(app.path) is not a waldo.Claunes.app bundle; refusing") }
        try FileOps.trash(app); print("moved \(app.path) to the Trash")
    case "handler":
        if args.count == 2 { print(ProtocolHandler.setDefault(bundleIdentifier: args[1]) ? "set" : "failed") }
        print(ProtocolHandler.current ?? "none")
    default: usage()
    }
} catch { fail("\(error.localizedDescription)") }
