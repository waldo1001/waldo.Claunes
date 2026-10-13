import ClaunesCore
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.claunes) { c in
                    HStack(spacing: 10) {
                        BadgeView(claune: c, size: 22)
                        Text(c.name)
                        Spacer()
                        if model.running.contains(c.id) {
                            Circle().fill(Color.green).frame(width: 8, height: 8).help("Running")
                        }
                    }
                    .tag(c.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button { model.showNewSheet = true } label: { Label("New Claune", systemImage: "plus") }
                }
            }
        } detail: {
            if let p = model.installationProblem {
                InstallationProblemView(message: p)
            } else if let id = model.selection, let c = model.claunes.first(where: { $0.id == id }) {
                DetailView(claune: c).id(c.id)   // fresh view (and @State) per selected Claune
            } else {
                EmptyStateView()
            }
        }
        .sheet(isPresented: $model.showNewSheet) { NewClauneSheet() }
        .sheet(item: $model.migrationCandidate) { cand in MigrationSheet(candidate: cand) }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onAppear { model.openWindowAction = { openWindow(id: "main") } }
    }
}

extension Migration.Candidate: Identifiable { public var id: String { url.path } }

struct BadgeView: View {
    let claune: Claune
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(Color(nsColor: IconGenerator.color(fromHex: claune.colorHex)))
            Text(claune.badge).font(.system(size: size * (claune.badge.count > 1 ? 0.38 : 0.52), weight: .semibold)).foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.square.stack").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No Claunes yet").font(.title2)
            Text("A Claune is a separate Claude Desktop profile with its own login, history and MCP servers.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("New Claune…") { model.showNewSheet = true }.keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

struct InstallationProblemView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
            Text("Claude Desktop is not installed").font(.title2)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Text("waldo.Claunes runs Anthropic's own Claude Desktop app. Install it in /Applications first.").font(.callout).multilineTextAlignment(.center).frame(maxWidth: 420)
            Link("Download Claude Desktop", destination: ClaudeInstallation.downloadURL)
        }
        .padding()
    }
}

struct DetailView: View {
    @EnvironmentObject var model: AppModel
    let claune: Claune
    @State private var name: String = ""
    @State private var badge: String = ""
    @State private var color: Color = .blue
    @State private var confirmDelete = false
    @State private var showSignInHint = false

    private var isRunning: Bool { model.running.contains(claune.id) }
    private var driftState: DriftState { model.drift[claune.id] ?? .upToDate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    IconPreview(badge: badge.isEmpty ? Claune.defaultBadge(for: name) : badge, colorHex: color.hexString)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Name", text: $name).font(.title2).textFieldStyle(.roundedBorder)
                        HStack {
                            ColorPicker("Color", selection: $color, supportsOpacity: false)
                            TextField("Badge", text: $badge).frame(width: 60).textFieldStyle(.roundedBorder)
                                .onChange(of: badge) { v in if v.count > 2 { badge = String(v.prefix(2)) } }
                            Spacer()
                            Button("Apply") { apply() }.disabled(!dirty || isRunning).keyboardShortcut(.defaultAction)
                        }
                        if isRunning && dirty { Text("Quit \(claune.name) before changing its name or icon.").font(.caption).foregroundStyle(.secondary) }
                    }
                }

                GroupBox("Status") {
                    Grid(alignment: .leading, verticalSpacing: 6) {
                        GridRow { Text("State").foregroundStyle(.secondary); Text(isRunning ? "Running" : "Not running") }
                        GridRow { Text("Data folder").foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: model.dataSizes[claune.id] ?? 0, countStyle: .file)) }
                        GridRow {
                            Text("App bundle").foregroundStyle(.secondary)
                            HStack {
                                Text(driftState.description)
                                if driftState.needsRebuild { Button("Resync") { model.resync(claune) }.disabled(isRunning) }
                            }
                        }
                        GridRow { Text("Built from").foregroundStyle(.secondary); Text("Claude \(claune.generatedFromVersion ?? "?")" + (model.installation.map { " (installed: \($0.version))" } ?? "")) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button { model.launch(claune) } label: { Label(isRunning ? "Show" : "Launch", systemImage: "play.fill") }
                        .keyboardShortcut("l")
                    Button("Reveal data folder") { model.revealData(claune) }
                    Button("Reveal app") { model.revealApp(claune) }
                    Button("Edit MCP config") { model.editMCPConfig(claune) }
                    Spacer()
                    Button("Resync") { model.resync(claune) }.disabled(isRunning)
                    Button(role: .destructive) { confirmDelete = true } label: { Text("Delete…") }.disabled(isRunning)
                }

                DisclosureGroup("Signing in to this Claune", isExpanded: $showSignInHint) {
                    Text("Claude signs in through your browser. If the browser is already logged in to another Claude account, that account ends up in this Claune. Sign out of claude.ai first or use a private window. waldo.Claunes routes the sign-in callback to whichever Claune is frontmost when you click Sign in.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear { load(claune) }
        .onChange(of: claune) { new in load(new) }   // use the new value: `self` here may be the previous view value
        .confirmationDialog("Move \(claune.name) to the Trash?", isPresented: $confirmDelete) {
            Button("Move app and data to Trash", role: .destructive) { model.delete(claune) }
        } message: { Text("The app in ~/Applications/Claunes and the data folder (login, history, MCP config) are moved to the Trash. Nothing is deleted permanently.") }
    }

    private var dirty: Bool {
        name != claune.name || (badge.isEmpty ? Claune.defaultBadge(for: name) : badge) != claune.badge || color.hexString.lowercased() != claune.colorHex.lowercased()
    }

    private func load(_ c: Claune) {
        name = c.name
        badge = c.badge
        color = Color(nsColor: IconGenerator.color(fromHex: c.colorHex))
    }

    private func apply() {
        var c = claune
        c.name = name
        c.badge = badge.isEmpty ? Claune.defaultBadge(for: name) : badge
        c.colorHex = color.hexString
        model.update(c)
    }
}

struct IconPreview: View {
    @EnvironmentObject var model: AppModel
    let badge: String
    let colorHex: String
    var body: some View {
        let base = model.installation?.iconURL.flatMap { NSImage(contentsOf: $0) }
        let img = IconGenerator.icon(badge: badge, colorHex: colorHex, pixels: 256, base: base)
        Image(nsImage: img).resizable().frame(width: 96, height: 96)
    }
}

extension Color {
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

struct NewClauneSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var badge = ""
    @State private var colorHex = Claune.palette[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Claune").font(.title2)
            HStack(spacing: 16) {
                IconPreview(badge: badge.isEmpty ? Claune.defaultBadge(for: name) : badge, colorHex: colorHex)
                VStack(alignment: .leading) {
                    TextField("Name (Work, Personal, …)", text: $name).textFieldStyle(.roundedBorder)
                    TextField("Badge (letter or emoji, optional)", text: $badge).textFieldStyle(.roundedBorder)
                        .onChange(of: badge) { v in if v.count > 2 { badge = String(v.prefix(2)) } }
                    HStack(spacing: 6) {
                        ForEach(Claune.palette, id: \.self) { hex in
                            Circle().fill(Color(nsColor: IconGenerator.color(fromHex: hex))).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.primary, lineWidth: hex == colorHex ? 2 : 0))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }
            }
            Text("Creates ~/Applications/Claunes/\(name.isEmpty ? "Name" : name).app with its own icon and an empty data folder. Claude Desktop itself is not modified.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { model.create(name: name, colorHex: colorHex, badge: badge); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct MigrationSheet: View {
    @EnvironmentObject var model: AppModel
    let candidate: Migration.Candidate
    @State private var name = "Main"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import your existing Claude Desktop data?").font(.title2)
            Text("Found \(ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file)) in \(candidate.url.path). It can be copied into a new Claune so you keep your login, history and MCP servers there. The original folder stays untouched as a backup (the copy shares disk blocks, so it is instant and costs no space).")
                .font(.callout)
            if Runtime.originalClaudeIsRunning {
                Label("Claude is running right now. Quit it first for a clean copy, or import anyway.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
            }
            TextField("Claune name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Not now") { model.declineMigration() }.keyboardShortcut(.cancelAction)
                Button("Import into \"\(name)\"") { model.migrate(into: name) }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
