import AppKit
import Foundation

/// Launching, activating and observing Claune processes. Thin wrapper over NSWorkspace.
public enum Runtime {
    public static func runningApplication(for claune: Claune) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: claune.bundleIdentifier).first
    }

    public static func isRunning(_ claune: Claune) -> Bool { runningApplication(for: claune) != nil }

    public static var originalClaudeIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeInstallation.bundleIdentifier).isEmpty
    }

    /// Bundle id of the frontmost app, if it is a Claune (or the original Claude).
    public static var frontmostBundleIdentifier: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    public static func frontmostClaune(in claunes: [Claune]) -> Claune? {
        guard let id = frontmostBundleIdentifier else { return nil }
        return claunes.first { $0.bundleIdentifier == id }
    }

    /// Launches via LaunchServices (so the launcher runs) or brings the running instance to the front.
    public static func launchOrActivate(_ claune: Claune, paths: ClaunesPaths) async throws {
        if let app = runningApplication(for: claune) {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
        let url = paths.appBundle(for: claune)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    public static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}

/// The `claude://` URL scheme handler. Claude re-registers itself at every launch, so the
/// Claune that was launched last gets the sign-in callback; we re-assert the frontmost one.
public enum ProtocolHandler {
    public static let scheme = "claude"

    public static var current: String? {
        LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String?
    }

    @discardableResult
    public static func setDefault(bundleIdentifier: String) -> Bool {
        LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleIdentifier as CFString) == 0
    }
}
