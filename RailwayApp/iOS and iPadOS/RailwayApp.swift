import SwiftUI
import UserNotifications

@main
struct RailwayApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("Railway", id: SceneID.main) {
            MainWindow()
        }
        .commands {
            RailwayCommands()
        }

        // On iPad, trips can open in their own windows.
        WindowGroup("Trip", id: SceneID.trip, for: String.self) { $journeyID in
            TripWindow(journeyID: journeyID)
        }
    }
}

/// A full window with its tabs.
private struct MainWindow: View {
    @State private var tabs = WindowTabs()
    @AppStorage(SettingsKey.alwaysShowTabBar) private var alwaysShowTabBar = false
    @AppStorage(SettingsKey.fullScreenCloseButton) private var fullScreenCloseButton = true
    @State private var windowScene: UIWindowScene?
    @State private var isFullScreen = false
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    #endif

    private var model: AppModel { tabs.selected.model }

    /// Like on the Mac: with more than one tab, or when always shown. Only with columns; with
    /// tabs at the bottom (iPhone, small iPad windows) there is no room for it.
    private var showsTabBar: Bool {
        model.usesSplitView && (tabs.tabs.count > 1 || alwaysShowTabBar)
    }

    /// In the corner of the columns' layout on iPad, where the window controls would be.
    private var showsCloseButton: Bool {
        fullScreenCloseButton && isFullScreen && model.usesSplitView
            && UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        TabContent(showsTabBar: showsTabBar, showsCloseButton: showsCloseButton)
            .environment(model)
            // Each tab is shown afresh; its search, results and trip are kept in its model.
            .id(tabs.selectedID)
            .coordinateSpace(.named(WindowTabBar.coordinateSpace))
            .overlay(alignment: .topLeading) {
                // The columns report where their toolbar ends in the content's coordinates (see
                // `tabBarSpace`); this overlay starts below the status bar in full screen, so its
                // offset from them is subtracted.
                GeometryReader { proxy in
                    let toolbarEnd = model.tabBarTop - proxy.frame(in: .named(WindowTabBar.coordinateSpace)).minY
                    // The line the toolbar's buttons are centred on, which the title of the
                    // connections column reports (its distance to the toolbar's end differs
                    // between windows and full screen).
                    let buttonsCentre = model.toolbarCentreY - proxy.frame(in: .global).minY
                    ZStack(alignment: .topLeading) {
                        if showsTabBar {
                            tabBar(below: toolbarEnd, buttonsCentre: buttonsCentre)
                        }
                        if showsCloseButton, let windowScene {
                            // Where the window controls are, centred on the toolbar's buttons.
                            FullScreenCloseButton {
                                UIApplication.shared.requestSceneSessionDestruction(windowScene.session, options: nil)
                            }
                            // On whole points: the × is an image, which snaps to the pixel grid, and
                            // would otherwise sit half a point off the circle's centre.
                            .position(
                                x: (FullScreenCloseButton.leading + FullScreenCloseButton.size / 2).rounded(),
                                y: buttonsCentre.rounded()
                            )
                        }
                    }
                }
            }
            .background {
                WindowObserver { scene, fullScreen in
                    if windowScene !== scene { windowScene = scene }
                    if isFullScreen != fullScreen { isFullScreen = fullScreen }
                }
                .ignoresSafeArea()
            }
            .focusedSceneValue(tabs)
            // iOS/iPadOS may end the app at any time once it is in the background.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    model.saveSearchInputs()
                    model.journeyStore.flush()
                }
            }
            #if DEBUG
            .task { await demo() }
            #endif
    }

    /// The tab bar right below the toolbar of the connections and trip columns.
    @ViewBuilder
    private func tabBar(below toolbarEnd: CGFloat, buttonsCentre: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(toolbarEnd, 0))
            WindowTabBar(tabs: tabs)
                .padding(.leading, max(model.tabBarLeading, 0))
            Spacer(minLength: 0)
        }
        // Toolbar and tabs read as one band over both columns, as on the Mac: cover the divider
        // between them within the toolbar, leaving only a short separator between the columns'
        // buttons.
        if !model.isCompact {
            ZStack(alignment: .topLeading) {
                // Up past the top of the content, where the window's edge is.
                Rectangle()
                    .fill(Color.windowBackground)
                    .frame(width: 3, height: max(toolbarEnd, 0) + 40)
                    .offset(x: -1.5, y: -40)
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 22)
                    .offset(x: -0.5, y: max(buttonsCentre - 11, 0))
            }
            .offset(x: model.tabBarDividerX)
            .allowsHitTesting(false)
        }
    }

    #if DEBUG
    /// Like the Mac's `DebugAutomation`: `RAILWAY_DEMO="From|To"` runs a search on launch,
    /// `RAILWAY_OPEN_TRIP=1` then opens the first connection, `RAILWAY_OPEN_WINDOW=1` opens it in
    /// its own window, `RAILWAY_NEW_WINDOW=1` opens a second main window and
    /// `RAILWAY_TAB=bookmarks|settings` selects a tab, `RAILWAY_NEW_TAB=1` opens a second window
    /// tab and `RAILWAY_SELECT_TAB=1` switches back to the first after the search.
    /// Only the first window opens another one, not the windows it opens.
    private static var openedDemoWindow = false
    private static var resizing = false

    private func demo() async {
        let environment = ProcessInfo.processInfo.environment
        // `RAILWAY_LANDSCAPE=1`: rotate, e.g. to see all columns on iPad.
        if environment["RAILWAY_LANDSCAPE"] != nil {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
        // `RAILWAY_WIDTH=1300`: resize the window, like on the Mac, e.g. to see all three columns.
        if let width = environment["RAILWAY_WIDTH"].flatMap(Double.init) {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                let size = CGSize(width: width, height: width * 0.7)
                scene.sizeRestrictions?.minimumSize = size
                scene.sizeRestrictions?.maximumSize = size
            }
        }
        // `RAILWAY_RESIZE=1`: keep resizing all windows, through the tabs, two- and three-column
        // layouts, like dragging their corners.
        if environment["RAILWAY_RESIZE"] != nil, !Self.resizing {
            Self.resizing = true
            Task {
                let widths: [CGFloat] = [1376, 900, 600, 1200, 500, 1050, 1376, 700]
                for step in 0..<200 {
                    try? await Task.sleep(for: .seconds(1.5))
                    let width = widths[step % widths.count]
                    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                        scene.sizeRestrictions?.maximumSize = CGSize(width: width, height: width * 0.75)
                    }
                    NSLog("RESIZE step %d width %.0f", step, width)
                }
            }
        }
        switch environment["RAILWAY_TAB"] {
        case "bookmarks": model.selectedTab = .bookmarks
        case "settings": model.selectedTab = .settings
        default: break
        }
        if environment["RAILWAY_NEW_WINDOW"] != nil, !Self.openedDemoWindow {
            Self.openedDemoWindow = true
            try? await Task.sleep(for: .seconds(2))
            openWindow(id: SceneID.main)
        }
        // `RAILWAY_HIDE_SIDEBAR=1`: hide the sidebar after launch, like on the Mac.
        if environment["RAILWAY_HIDE_SIDEBAR"] != nil {
            try? await Task.sleep(for: .seconds(1))
            model.toggleSidebar()
        }
        if environment["RAILWAY_NEW_TAB"] != nil, !Self.openedDemoWindow {
            Self.openedDemoWindow = true
            tabs.newTab()
        }
        let model = model
        let parts = environment["RAILWAY_DEMO"]?.split(separator: "|").map(String.init) ?? []
        guard parts.count == 2 else { return }
        model.run(SavedSearch(origin: parts[0], destination: parts[1]))
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(1))
            if let first = model.result?.journeys.first {
                if environment["RAILWAY_OPEN_TRIP"] != nil { model.open(first) }
                // `RAILWAY_SELECT_TAB=1`: then switch tabs, like ⌘1.
                if let number = environment["RAILWAY_SELECT_TAB"].flatMap(Int.init) {
                    tabs.select(number: number)
                }
                if environment["RAILWAY_OPEN_WINDOW"] != nil, !Self.openedDemoWindow {
                    Self.openedDemoWindow = true
                    openWindow(id: SceneID.trip, value: first.id)
                }
                return
            }
        }
    }
    #endif
}

/// One tab of a window: the Mac's columns when there is room (iPad), tabs at the bottom
/// otherwise (iPhone, small iPad windows). Resizing an iPad window switches between them.
private struct TabContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var showsTabBar: Bool
    var showsCloseButton: Bool

    var body: some View {
        @Bindable var model = model
        Group {
            if model.usesSplitView {
                ContentView()
            } else {
                MainTabs()
            }
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            model.usesSplitView = sizeClass == .regular
        }
        .onChange(of: showsTabBar, initial: true) { _, shows in
            model.tabBarVisible = shows
        }
        .onChange(of: showsCloseButton, initial: true) { _, shows in
            model.showsCloseButton = shows
        }
        .sheet(isPresented: $model.isTripPresented) {
            TripSheet()
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsSheet()
        }
        .focusedSceneValue(model)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show trip notifications even while Railway is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
