import SwiftUI

/// Menu commands with the keyboard shortcuts of Railway; they act on the frontmost window.
struct RailwayCommands: Commands {
    @FocusedValue(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.alwaysShowTabBar) private var alwaysShowTabBar = false
    #if os(iOS)
    /// iPad windows hold their tabs themselves (see `WindowTabs`).
    @FocusedValue(WindowTabs.self) private var tabs
    #endif

    private func selectTab(_ number: Int) {
        #if os(macOS)
        guard let tabs = NSApp.keyWindow?.tabbedWindows, !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        tabs[index].makeKeyAndOrderFront(nil)
        #else
        tabs?.select(number: number)
        #endif
    }

    /// In the Window menu, above the list of windows (iPadOS has no such list; its window
    /// arrangement items come first instead).
    #if os(macOS)
    private static let tabCommandsPlacement = CommandGroupPlacement.windowList
    #else
    private static let tabCommandsPlacement = CommandGroupPlacement.windowArrangement
    #endif

    var body: some Commands {
        #if os(macOS)
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

        #else
        // iPad has no Settings scene; the settings open as a sheet of the frontmost window.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model?.isSettingsPresented = true }
                .keyboardShortcut(",")
                .disabled(model?.hasSearch != true)
        }
        #endif

        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: SceneID.main) }
                .keyboardShortcut("n")
            #if os(macOS)
            Button("New Tab") {
                WindowController.pendingTabParent = NSApp.keyWindow?.tabbingIdentifier == WindowController.mainTabbingIdentifier
                    ? NSApp.keyWindow : nil
                openWindow(id: SceneID.main)
            }
            .keyboardShortcut("t")
            #else
            Button("New Tab") { tabs?.newTab() }
                .keyboardShortcut("t")
                .disabled(tabs == nil)
            // The Mac closes tabs with ⌘W through its window menu.
            Button("Close Tab") { tabs?.closeSelected() }
                .keyboardShortcut("w")
                .disabled(tabs?.canClose != true)
            #endif
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
        CommandGroup(before: Self.tabCommandsPlacement) {
            #if os(iOS)
            // The Mac's window menu has these for its native tabs.
            Button("Show Previous Tab") { tabs?.selectPrevious() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(tabs?.canClose != true)
            Button("Show Next Tab") { tabs?.selectNext() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(tabs?.canClose != true)
            Divider()
            #endif
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
