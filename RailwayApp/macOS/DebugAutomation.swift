#if DEBUG
import AppKit
import SwiftUI

/// Development helpers driven by environment variables; compiled into debug builds only.
///
/// - `RAILWAY_DEMO="From|To"`: fill in the search, run it and select the first connection.
/// - `RAILWAY_SNAPSHOT=/path/prefix`: write PNG snapshots of the main window every few seconds.
/// - `RAILWAY_EXPAND=1`: show stops and announcements of legs expanded.
/// - `RAILWAY_TYPE="Wien"`: type into the "From" field to show suggestions.
/// - `RAILWAY_WIDTH=900`: resize the window, e.g. to test the compact layout.
/// - `RAILWAY_OPEN_TRIP=1`: open the connection selected by `RAILWAY_DEMO` in its own window.
/// - `RAILWAY_NEW_TAB=1`: open a second tab after launch.
/// - `RAILWAY_OPTIONS=1`: open the search options sheet.
/// - `RAILWAY_TOOLBAR_MODE=iconAndLabel|label|icon`: set the toolbar's display mode.
/// - `RAILWAY_SETTINGS=/path`: open the Settings window and write its title to the file.
/// - `RAILWAY_HIDE_SIDEBAR=1`: hide the sidebar after launch.
/// - `RAILWAY_GALLERY=1`: open a window comparing segmented control variants.
/// - `RAILWAY_TOGGLE_TAB_BAR=1`: toggle "Always Show Tab Bar" after launch.
/// - `RAILWAY_BOOKMARK=1`: bookmark the connection selected by `RAILWAY_DEMO`.
enum DebugAutomation {
    static let expand = ProcessInfo.processInfo.environment["RAILWAY_EXPAND"] != nil
    private static var started = false

    static func start(model: AppModel, openWindow: OpenWindowAction, openSettings: OpenSettingsAction) {
        // Only automate the first window, not tabs or windows opened later.
        guard !started else { return }
        started = true
        let environment = ProcessInfo.processInfo.environment

        if environment["RAILWAY_NEW_TAB"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2))
                WindowController.pendingTabParent = NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
                openWindow(id: SceneID.main)
            }
        }

        if let width = environment["RAILWAY_WIDTH"].flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(1))
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                    var frame = window.frame
                    frame.size.width = width
                    window.setFrame(frame, display: true)
                }
            }
        }

        if let demo = environment["RAILWAY_DEMO"] {
            let parts = demo.split(separator: "|").map(String.init)
            if parts.count == 2 {
                model.run(SavedSearch(origin: parts[0], destination: parts[1]))
                Task {
                    for _ in 0..<40 {
                        try? await Task.sleep(for: .seconds(1))
                        if let result = model.result, !result.journeys.isEmpty {
                            // Prefer a connection with changes, to show transitions.
                            let first = result.journeys.first { $0.journey.transitions > 0 } ?? result.journeys[0]
                            model.selectedJourney = first
                            if environment["RAILWAY_OPEN_TRIP"] != nil {
                                openWindow(id: SceneID.trip, value: first.id)
                            }
                            if environment["RAILWAY_BOOKMARK"] != nil, !model.journeyStore.contains(first) {
                                model.toggleBookmark(first)
                            }
                            return
                        }
                    }
                }
            }
        }

        if let mode = environment["RAILWAY_TOOLBAR_MODE"] {
            Task {
                try? await Task.sleep(for: .seconds(2))
                let displayMode: NSToolbar.DisplayMode = switch mode {
                case "iconAndLabel": .iconAndLabel
                case "label": .labelOnly
                default: .iconOnly
                }
                for window in NSApp.windows { window.toolbar?.displayMode = displayMode }
            }
        }

        if let path = environment["RAILWAY_SETTINGS"] {
            Task {
                try? await Task.sleep(for: .seconds(2))
                openSettings()
                try? await Task.sleep(for: .seconds(2))
                let titles = NSApp.windows.filter(\.isVisible).map(\.title)
                try? titles.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }

        if environment["RAILWAY_HIDE_SIDEBAR"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(3))
                model.toggleSidebar()
            }
        }

        if environment["RAILWAY_GALLERY"] != nil {
            DebugGallery.open()
        }

        if environment["RAILWAY_TOGGLE_TAB_BAR"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(3))
                // Same as choosing View ▸ Always Show Tab Bar.
                UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: SettingsKey.alwaysShowTabBar), forKey: SettingsKey.alwaysShowTabBar)
            }
        }

        if let path = environment["RAILWAY_DUMP_VIEWS"] {
            Task {
                try? await Task.sleep(for: .seconds(8))
                dumpViews(to: path)
            }
        }

        if let prefix = environment["RAILWAY_SNAPSHOT"] {
            Task {
                for index in 1...6 {
                    try? await Task.sleep(for: .seconds(4))
                    snapshot(to: "\(prefix)-\(index).png")
                    snapshotOffscreen(NavigationStack { SearchView() }.environment(model), size: CGSize(width: 320, height: 760), to: "\(prefix)-sidebar-\(index).png")
                    if index == 1 {
                        snapshotOffscreen(SettingsView(), size: CGSize(width: 520, height: 320), to: "\(prefix)-settings.png")
                        snapshotOffscreen(SearchOptionsSheet(), size: CGSize(width: 500, height: 560), to: "\(prefix)-options.png")
                    }
                }
            }
        }
    }

    /// Lists toolbar items and the views in the toolbar area, to debug window chrome.
    private static func dumpViews(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
              let root = window.contentView?.superview else { return }
        var lines = ["toolbar displayMode=\(window.toolbar?.displayMode.rawValue ?? 99) allowsDisplayModeCustomization=\(window.toolbar?.allowsDisplayModeCustomization ?? false)", "toolbar items:"]
        for item in window.toolbar?.items ?? [] {
            lines.append("  \(type(of: item)) \(item.itemIdentifier.rawValue) label=\(item.label) tooltip=\(item.toolTip ?? "-") badge=\(item.badge != nil) view=\(item.view.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        let toolbarBottom = window.contentLayoutRect.maxY
        func visit(_ view: NSView, depth: Int) {
            let frame = view.convert(view.bounds, to: nil)
            if frame.maxY > toolbarBottom - 1, frame.width < 40 || frame.height < 120 || depth < 6 {
                lines.append(String(repeating: "  ", count: depth) + "\(type(of: view)) \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))\(view.isHidden ? " hidden" : "")")
            }
            view.subviews.forEach { visit($0, depth: depth + 1) }
        }
        visit(root, depth: 0)
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func snapshot(to path: String) {
        for (index, window) in NSApp.windows.filter({ $0.isVisible && $0.canBecomeKey }).enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView else { continue }
            write(view, to: index == 0 ? path : path.replacing(".png", with: "-window\(index).png"))
        }
    }

    /// The glass sidebar is composited outside the app, so render views separately for inspection.
    static func snapshotOffscreen(_ content: some View, size: CGSize, to path: String) {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: 0), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        Task {
            try? await Task.sleep(for: .seconds(1))
            write(host, to: path)
            window.orderOut(nil)
        }
    }

    private static func write(_ view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
