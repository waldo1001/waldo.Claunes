import Foundation

/// A long-running executable for tests that need a process executing from inside a bundle.
/// Built from source instead of copying /bin/sleep: on some Macs (seen on an Intel Mac, macOS 15.8) a relocated copy of
/// Apple's sleep never finishes exiting (state UE, unkillable until reboot), which hangs the test run in waitUntilExit.
enum TestResident {
    struct BuildFailed: Error { let status: Int32 }

    /// Writes a binary to `url` that sleeps for argv[1] seconds (default 30).
    static func make(at url: URL) throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("claunes-resident-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let source = dir.appendingPathComponent("resident.c")
        try """
        #include <stdlib.h>
        #include <unistd.h>
        int main(int argc, char **argv) { sleep(argc > 1 ? atoi(argv[1]) : 30); return 0; }
        """.write(to: source, atomically: true, encoding: .utf8)
        let cc = Process()
        cc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        cc.arguments = ["cc", "-o", url.path, source.path]
        try cc.run()
        cc.waitUntilExit()
        guard cc.terminationStatus == 0 else { throw BuildFailed(status: cc.terminationStatus) }
    }
}
