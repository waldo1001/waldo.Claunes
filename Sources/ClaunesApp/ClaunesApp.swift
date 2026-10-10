import AppKit
import ClaunesCore
import SwiftUI

@main
struct ClaunesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("waldo.Claunes", id: "main") {
            MainWindow()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 820, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Claune…") { model.showNewSheet = true }.keyboardShortcut("n")
            }
        }

        MenuBarExtra {
            MenuBarMenu().environmentObject(model)
        } label: {
            MenuBarLabel().environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.openMainWindow() }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
