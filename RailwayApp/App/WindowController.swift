import AppKit
import SwiftUI

/// Window-level behaviour SwiftUI has no API for: native tabs, the "Always Show Tab Bar" option
/// and showing the toolbar background only while the pointer is over it.
@MainActor
final class WindowController {
    private weak var window: NSWindow?
    private weak var model: AppModel?
    private var tabBarObservation: NSKeyValueObservation?
    private var mouseMonitor: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    /// The last "Always Show Tab Bar" value seen, to react only when that setting changes.
    private var alwaysShowTabBar = UserDefaults.standard.bool(forKey: SettingsKey.alwaysShowTabBar)
    /// Set while toggling the tab bar, which itself writes window state to the user defaults.
    private var isUpdatingTabBar = false

    /// The window that ⌘T or the tab bar's "+" was used in; the next main window joins it as a tab.
    static weak var pendingTabParent: NSWindow?

    static let mainTabbingIdentifier = "railway-main"

    func attach(to window: NSWindow, model: AppModel) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        self.model = model

        if model.hasSearch {
            // ⌘N follows the system's "Prefer tabs" setting; ⌘T always adds a tab.
            window.tabbingMode = .automatic
            window.tabbingIdentifier = Self.mainTabbingIdentifier
            if let parent = Self.pendingTabParent, parent !== window {
                Self.pendingTabParent = nil
                parent.addTabbedWindow(window, ordered: .above)
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            // Trip windows are small companions; keep them out of the main windows' tabs.
            window.tabbingMode = .disallowed
        }

        window.acceptsMouseMovedEvents = true
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited]) { [weak self] event in
            self?.trackPointer(event)
            return event
        }

        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDividerMask() }
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            notificationTokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateTabBar() }
            })
        }
        // Any default changing posts this, including the ones AppKit writes when the tab bar is
        // toggled, so only react to "Always Show Tab Bar" itself changing.
        notificationTokens.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let value = UserDefaults.standard.bool(forKey: SettingsKey.alwaysShowTabBar)
                guard value != self.alwaysShowTabBar else { return }
                self.alwaysShowTabBar = value
                self.updateTabBar(settingChanged: true)
            }
        })
        observeTabGroup()
        updateTabBar()
    }

    func detach() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens = []
        tabBarObservation = nil
    }

    private func observeTabGroup() {
        tabBarObservation = window?.tabGroup?.observe(\.isTabBarVisible, options: [.initial, .new]) { [weak self] group, _ in
            let visible = group.isTabBarVisible
            DispatchQueue.main.async {
                guard let self, let model = self.model else { return }
                if model.tabBarVisible != visible {
                    withAnimation(.easeInOut(duration: 0.2)) { model.tabBarVisible = visible }
                }
                self.updateDividerMask()
            }
        }
    }

    /// Applies "Always Show Tab Bar" and keeps the model in sync with the tab bar.
    ///
    /// - Parameter settingChanged: Only when the option is switched off is a single tab's bar
    ///   hidden again; otherwise a tab bar shown with View ▸ Show Tab Bar stays.
    private func updateTabBar(settingChanged: Bool = false) {
        guard let window, let model, model.hasSearch, !isUpdatingTabBar else { return }
        isUpdatingTabBar = true
        defer { isUpdatingTabBar = false }
        // Joining a tab group replaces the window's group.
        observeTabGroup()
        guard let group = window.tabGroup else { return }
        let alwaysShow = alwaysShowTabBar
        if alwaysShow, !group.isTabBarVisible {
            window.toggleTabBar(nil)
        } else if settingChanged, !alwaysShow, group.isTabBarVisible, group.windows.count == 1 {
            window.toggleTabBar(nil)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let model = self.model, let visible = self.window?.tabGroup?.isTabBarVisible else { return }
            if model.tabBarVisible != visible { model.tabBarVisible = visible }
            self.updateDividerMask()
        }
    }

    /// While tabs show, the toolbar and tab bar read as one bar over the connections and trip
    /// columns: the column divider is hidden within that bar. The toolbar's own short separator
    /// between the columns' buttons stays.
    func updateDividerMask() {
        guard let window, let model, let root = window.contentView else { return }
        // Let SwiftUI finish laying out the split view first.
        DispatchQueue.main.async {
            let band = model.tabBarVisible && model.hasSearch
                ? window.frame.height - window.contentLayoutRect.maxY : 0
            for divider in Self.dividers(in: root) {
                guard let layer = divider.layer ?? { divider.wantsLayer = true; return divider.layer }() else { continue }
                if band > 0 {
                    let mask = layer.mask ?? CALayer()
                    mask.backgroundColor = NSColor.black.cgColor
                    // Layers of unflipped views start at the bottom: keep everything below the bar.
                    mask.frame = CGRect(x: 0, y: 0, width: divider.bounds.width, height: max(divider.bounds.height - band, 0))
                    layer.mask = mask
                } else {
                    layer.mask = nil
                }
            }
        }
    }

    /// The visible dividers between split view columns (the sidebar's is zero-width).
    private static func dividers(in view: NSView) -> [NSView] {
        var result: [NSView] = []
        for subview in view.subviews {
            if String(describing: type(of: subview)) == "NSSplitDividerView", subview.frame.width > 0 {
                result.append(subview)
            }
            result += dividers(in: subview)
        }
        return result
    }

    /// The toolbar background shows while the pointer is over the toolbar above the trip details.
    private func trackPointer(_ event: NSEvent) {
        guard let window, let model else { return }
        let hovering: Bool
        if event.window === window {
            let location = event.locationInWindow
            let toolbarBottom = window.contentLayoutRect.maxY
            hovering = location.y >= toolbarBottom && location.x >= model.detailMinX
        } else {
            hovering = false
        }
        if hovering != model.toolbarHovered {
            withAnimation(.easeOut(duration: 0.2)) { model.toolbarHovered = hovering }
        }
    }
}

/// Hands the hosting `NSWindow` to a `WindowController`.
struct WindowAccessor: NSViewRepresentable {
    var model: AppModel

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onWindow = { [controller = context.coordinator] window in
            controller.attach(to: window, model: model)
        }
        return view
    }

    func updateNSView(_ view: AccessorView, context: Context) {}

    static func dismantleNSView(_ view: AccessorView, coordinator: WindowController) {
        coordinator.detach()
    }

    func makeCoordinator() -> WindowController {
        WindowController()
    }

    final class AccessorView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

extension View {
    /// Connects the view's window to native tabbing and toolbar hover tracking.
    func windowBehavior(_ model: AppModel) -> some View {
        background(WindowAccessor(model: model))
    }
}
