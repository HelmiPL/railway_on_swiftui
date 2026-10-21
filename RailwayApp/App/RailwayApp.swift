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

enum SceneID {
    static let main = "main"
    static let trip = "trip"
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

/// Menu commands with the keyboard shortcuts of Railway; they act on the frontmost window.
struct RailwayCommands: Commands {
    @FocusedValue(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.alwaysShowTabBar) private var alwaysShowTabBar = false

    private func selectTab(_ number: Int) {
        guard let tabs = NSApp.keyWindow?.tabbedWindows, !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        tabs[index].makeKeyAndOrderFront(nil)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Railway") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .credits: NSAttributedString(
                        string: String(localized: "A native macOS version of Railway, the travel information app by Julian Schmidhuber, Markus Göllnitz and contributors.\n\nTravel data is provided by the respective transit networks."),
                        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                    ),
                ])
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: SceneID.main) }
                .keyboardShortcut("n")
            Button("New Tab") {
                WindowController.pendingTabParent = NSApp.keyWindow?.tabbingIdentifier == WindowController.mainTabbingIdentifier
                    ? NSApp.keyWindow : nil
                openWindow(id: SceneID.main)
            }
            .keyboardShortcut("t")
        }

        CommandGroup(before: .toolbar) {
            Button(model?.isSidebarVisible == false ? "Show Sidebar" : "Hide Sidebar") {
                model?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(model?.hasSearch != true)
            Toggle("Always Show Tab Bar", isOn: $alwaysShowTabBar)
            Divider()
        }

        // ⌘1–⌘8 select a tab by position, ⌘9 the last one, like Safari.
        CommandGroup(before: .windowList) {
            ForEach(1...9, id: \.self) { number in
                Button(number == 9 ? "Show Last Tab" : "Show Tab \(number)") {
                    selectTab(number)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")))
            }
            Divider()
        }

        CommandMenu("Trip") {
            Button("Search") { model?.search() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model?.canSearch != true)
            Button("Find Start…") { model?.focusFrom() }
                .keyboardShortcut("f")
                .disabled(model?.hasSearch != true)
            Button("Swap Start and Destination") { model?.swapPlaces() }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .disabled(model?.hasSearch != true)

            Divider()

            Button(model?.isResultBookmarked == true ? "Remove Search Bookmark" : "Bookmark This Search") {
                model?.toggleResultBookmark()
            }
            .keyboardShortcut("s")
            .disabled(model?.result == nil)

            Button("Earlier Connections") { model?.loadEarlier() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(model?.result == nil)
            Button("Later Connections") { model?.loadLater() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(model?.result == nil)

            Divider()

            let journey = model?.selectedJourney
            let bookmarked = journey.map { RailwayServices.shared.journeyStore.contains($0) } ?? false
            let watched = journey.map { RailwayServices.shared.journeyStore.isWatched($0) } ?? false

            Button("Open Trip in New Window") {
                if let journey { openWindow(id: SceneID.trip, value: journey.id) }
            }
            .keyboardShortcut("o")
            .disabled(journey == nil || model?.hasSearch != true)

            Button(bookmarked ? "Remove Trip Bookmark" : "Bookmark This Trip") {
                if let journey { model?.toggleBookmark(journey) }
            }
            .keyboardShortcut("d")
            .disabled(journey == nil)

            Button(watched ? "Stop Watching This Trip" : "Watch This Trip") {
                if let journey { model?.toggleWatch(journey) }
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(!bookmarked)

            Button("Refresh This Trip") {
                if let journey { model?.refresh(journey) }
            }
            .keyboardShortcut("r")
            .disabled(journey == nil || journey?.refreshInProgress == true)
        }
    }
}
