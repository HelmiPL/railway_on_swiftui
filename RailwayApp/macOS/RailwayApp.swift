import SwiftUI
import UserNotifications

@main
struct RailwayApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("Railway", id: SceneID.main) {
            MainWindow()
        }
        .defaultSize(width: 1180, height: 720)
        // The toolbar is designed for icons; labels don't fit the sidebar's toolbar and break its
        // custom items, so "Icon and Text" and "Text Only" aren't offered.
        .windowToolbarLabelStyle(fixed: .iconOnly)
        .commands {
            RailwayCommands()
        }

        WindowGroup("Trip", id: SceneID.trip, for: String.self) { $journeyID in
            TripWindow(journeyID: journeyID)
        }
        .defaultSize(width: 560, height: 720)
        .windowToolbarLabelStyle(fixed: .iconOnly)
        .commandsRemoved()

        Settings {
            SettingsView()
        }
    }
}

/// A full window with search, connections and trip details.
private struct MainWindow: View {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        ContentView()
            .environment(model)
            .focusedSceneValue(model)
            .onAppear {
                AppDelegate.openNewWindow = { openWindow(id: SceneID.main) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                model.saveSearchInputs()
                model.journeyStore.flush()
            }
            #if DEBUG
            .task { DebugAutomation.start(model: model, openWindow: openWindow, openSettings: openSettings) }
            #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Opens a new main window; set by the first main window, as only views can open windows.
    static var openNewWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    // "New Window" when right-clicking the app icon in the Dock.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: String(localized: "New Window"), action: #selector(newWindow), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func newWindow() {
        NSApp.activate()
        Self.openNewWindow?()
    }

    /// The "+" button of the native tab bar.
    @objc func newWindowForTab(_ sender: Any?) {
        WindowController.pendingTabParent = NSApp.keyWindow
        Self.openNewWindow?()
    }

    // Show trip notifications even while Railway is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
