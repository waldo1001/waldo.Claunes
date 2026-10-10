import Darwin
import Foundation

/// Which processes execute a binary that lives under a directory: the kernel's view (proc_pidpath), independent of
/// LaunchServices bookkeeping, and including the calling process itself. Used to refuse rebuilding a Claune bundle
/// while anything runs from it: the launcher, Claude, or one of its helpers (see SPIKE.md, "drift repair").
public enum ProcessScan {
    public static func pids(executingUnder directory: URL) -> [pid_t] {
        // realpath(3), not Foundation's resolvingSymlinksInPath: that one rewrites /private/tmp to /tmp, proc_pidpath does not.
        guard let real = realpath(directory.path, nil) else { return [] }
        let prefix = String(cString: real) + "/"
        free(real)
        var count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        count += 32 // room for processes started between the two calls
        var pids = [pid_t](repeating: 0, count: Int(count))
        let filled = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN)) // PROC_PIDPATHINFO_MAXSIZE, a macro Swift does not import
        var result: [pid_t] = []
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard len > 0 else { continue } // not ours to inspect (other user) or already gone
            let path = String(decoding: buffer.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if path.hasPrefix(prefix) { result.append(pid) }
        }
        return result
    }

    /// Blocks until `pid` has exited or `timeout` elapsed. Returns true when it is gone.
    public static func waitForExit(pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while kill(pid, 0) == 0 || errno == EPERM {
            if Date() > deadline { return false }
            usleep(50_000)
        }
        return true
    }
}
