import AppKit
import ClaunesCore
import SwiftUI

/// Colored letter of the frontmost Claune, or a neutral glyph.
struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let c = model.frontmost {
            Image(nsImage: MenuBarLabel.image(for: c))
        } else {
            Image(systemName: "person.2.square.stack")
        }
    }

    static func image(for c: Claune) -> NSImage {
        let img = IconGenerator.tile(badge: c.badge, colorHex: c.colorHex, pixels: 36, inset: 0.0)
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = false
        return img
    }
}

struct MenuBarMenu: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.claunes.isEmpty {
            Text("No Claunes yet")
        }
        ForEach(model.claunes) { c in
            Button {
                model.launch(c)
            } label: {
                HStack {
                    Image(nsImage: MenuBarLabel.image(for: c))
                    Text(c.name + (model.running.contains(c.id) ? "  •" : ""))
                }
            }
        }
        Divider()
        Button("New Claune…") { model.showNewSheet = true; model.openMainWindow(); openWindow(id: "main") }
        Button("Open waldo.Claunes") { openWindow(id: "main"); model.openMainWindow() }
        Divider()
        Button("Quit waldo.Claunes") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
