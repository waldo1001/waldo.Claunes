import AppKit
import ClaunesCore
import Combine
import SwiftUI

/// Observable state for the whole app. Main-actor only.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var claunes: [Claune] = []
    @Published private(set) var running: Set<UUID> = []
    @Published private(set) var frontmost: Claune?
    @Published var selection: UUID?
    @Published var showNewSheet = false
    @Published var errorMessage: String?
    @Published private(set) var installation: ClaudeInstallation?
    @Published private(set) var installationProblem: String?
    @Published var migrationCandidate: Migration.Candidate?
    @Published private(set) var drift: [UUID: DriftState] = [:]
    @Published private(set) var dataSizes: [UUID: Int64] = [:]

    let paths = ClaunesPaths.standard
    private(set) var manager: ClauneManager?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    // MARK: lifecycle

    func start() {
        do {
            manager = try ClauneManager(paths: paths, launcherBinary: AppModel.launcherURL)
        } catch {
            errorMessage = "Could not read profiles.json: \(error.localizedDescription)"
        }
        refreshInstallation()
        reload()
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshRunning() } })
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshRunning() } })
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in Task { @MainActor in self?.activated(n) } })
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.refreshDrift() } }
        if let m = manager, !m.store.document.migrationOfferShown, let cand = Migration.detectOriginalData(paths: paths) {
            migrationCandidate = cand
        }
        if claunes.isEmpty || migrationCandidate != nil { openMainWindow() }
    }

    static var launcherURL: URL {
        // Inside the app bundle (Contents/MacOS/claune-launcher) or next to the executable in a SwiftPM build.
        let exeDir = Bundle.main.executableURL!.deletingLastPathComponent()
        return exeDir.appendingPathComponent("claune-launcher")
    }

    func refreshInstallation() {
        do {
            installation = try ClaudeInstallation.locate(paths: paths)
            installationProblem = nil
        } catch {
            installation = nil
            installationProblem = error.localizedDescription
        }
    }

    func reload() {
        guard let m = manager else { return }
        try? m.store.reload()
        claunes = m.store.claunes
        if selection == nil || !claunes.contains(where: { $0.id == selection }) { selection = claunes.first?.id }
        refreshRunning()
        refreshDrift()
        refreshSizes()
    }

    func refreshRunning() {
        running = Set(claunes.filter { Runtime.isRunning($0) }.map(\.id))
        frontmost = Runtime.frontmostClaune(in: claunes)
    }

    func refreshDrift() {
        refreshInstallation()
        guard let m = manager else { return }
        var d: [UUID: DriftState] = [:]
        for c in claunes { d[c.id] = m.drift(c) }
        drift = d
    }

    func refreshSizes() {
        guard let m = manager else { return }
        let list = claunes
        Task.detached { [paths = self.paths] in
            var sizes: [UUID: Int64] = [:]
            for c in list { sizes[c.id] = FileOps.folderSize(paths.dataDir(for: c)) }
            let result = sizes
            await MainActor.run { self.dataSizes = result }
            _ = m
        }
    }

    private func activated(_ n: Notification) {
        refreshRunning()
        // Sign-in routing: the frontmost Claude instance gets the claude:// callback (see SPIKE.md).
        guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bid = app.bundleIdentifier else { return }
        if claunes.contains(where: { $0.bundleIdentifier == bid }) || bid == ClaudeInstallation.bundleIdentifier {
            if ProtocolHandler.current != bid { ProtocolHandler.setDefault(bundleIdentifier: bid) }
        }
    }

    // MARK: actions

    /// Set by the UI (SwiftUI's openWindow action); the menu bar item and the delegate use it.
    var openWindowAction: (() -> Void)?

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "waldo.Claunes" }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?()
        }
    }

    func run(_ title: String, _ body: () throws -> Void) {
        do { try body() } catch { errorMessage = "\(title): \(error.localizedDescription)" }
        reload()
    }

    func create(name: String, colorHex: String, badge: String) {
        run("Create Claune") {
            let c = try manager!.create(name: name, colorHex: colorHex, badge: badge.isEmpty ? nil : badge)
            selection = c.id
        }
    }

    func update(_ c: Claune) { run("Update Claune") { try manager!.update(c) } }
    func resync(_ c: Claune) { run("Resync") { try manager!.resync(c) } }

    func delete(_ c: Claune) {
        run("Delete Claune") {
            if Runtime.isRunning(c) { throw NSError(domain: "Claunes", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(c.name) is running. Quit it first."]) }
            try manager!.delete(c)
        }
    }

    func launch(_ c: Claune) {
        Task {
            // Drift is repaired here, before the launch, never by the Claune's own launcher (SPIKE.md, drift repair).
            do { _ = try manager?.repairIfNeeded(c) } catch { errorMessage = "Resync \(c.name): \(error.localizedDescription)" }
            do { try await Runtime.launchOrActivate(c, paths: paths) } catch { errorMessage = "Launch \(c.name): \(error.localizedDescription)" }
            refreshRunning()
            refreshDrift()
        }
    }

    func revealData(_ c: Claune) { Runtime.reveal(paths.dataDir(for: c)) }
    func revealApp(_ c: Claune) { Runtime.reveal(paths.appBundle(for: c)) }

    func editMCPConfig(_ c: Claune) {
        run("Edit MCP config") {
            let url = try manager!.ensureMCPConfig(c)
            NSWorkspace.shared.open(url)
        }
    }

    func migrate(into name: String) {
        run("Import existing Claude data") {
            let c = try manager!.create(name: name)
            try Migration.importOriginalData(into: c, paths: paths)
            try manager!.store.setMigrationOfferShown()
            migrationCandidate = nil
            selection = c.id
        }
    }

    func declineMigration() {
        run("Migration") { try manager!.store.setMigrationOfferShown(); migrationCandidate = nil }
    }
}
