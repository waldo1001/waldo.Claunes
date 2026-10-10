import Darwin
import Foundation

/// Hand-off protocol between a Claune's launcher and the installed waldo.Claunes CLI (see SPIKE.md, drift repair).
/// The launcher never rebuilds the bundle it runs from. On drift it starts `claunes relaunch <id> --after-pid <pid>`
/// detached and exits; the CLI waits for that pid, rebuilds (BundleBuilder refuses while anything still runs from
/// the bundle) and launches the fresh bundle with `marker`, which tells the new launcher not to hand off again.
public enum Relaunch {
    /// Argument the CLI passes when it launches a Claune it has just repaired; the launcher then never hands off again.
    public static let marker = "--claune-repaired"

    public static func strip(_ args: [String]) -> (args: [String], repaired: Bool) {
        (args.filter { $0 != marker }, args.contains(marker))
    }

    /// True when `cli` understands `relaunch` (older installs print usage and exit 2).
    public static func cliSupportsRelaunch(_ cli: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: cli.path) else { return false }
        let p = Process()
        p.executableURL = cli
        p.arguments = ["relaunch", "--probe"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Starts `executable` in its own session so it survives our exit. Returns the pid, or nil when spawning failed.
    @discardableResult
    public static func spawnDetached(_ executable: URL, arguments: [String]) -> pid_t? {
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd: Int32 in 0...2 { posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0) }
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable.path, &actions, &attr, argv, environ)
        return rc == 0 ? pid : nil
    }
}
