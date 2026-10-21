import SwiftUI

/// The main window: search, connections and trip details side by side, like Railway's split views.
///
/// When the window is too narrow for three columns, trips open in their own windows instead.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    /// Below this width the trip details move to separate windows (sheets on iPad).
    #if os(macOS)
    nonisolated private static let compactWidth: CGFloat = 1000
    #else
    /// iPadOS needs more room before it shows three columns side by side; below it, it hides the
    /// sidebar, and with it the search.
    #if DEBUG
    // `RAILWAY_COMPACT_WIDTH=900`: see the three columns in a portrait simulator.
    nonisolated private static let compactWidth: CGFloat =
        ProcessInfo.processInfo.environment["RAILWAY_COMPACT_WIDTH"].flatMap(Double.init).map { CGFloat($0) } ?? 1100
    #else
    nonisolated private static let compactWidth: CGFloat = 1100
    #endif
    #endif

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isCompact {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    sidebar
                } detail: {
                    JourneysView()
                        #if os(iOS)
                        .tabBarGap(model)
                        .toolbarBand(model.contentToolbarBand)
                        #endif
                        .tabBarSpace(model, startsTabBar: true)
                }
            } else {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    sidebar
                } content: {
                    JourneysView()
                        .tabBarGap(model)
                        .toolbarBand(model.contentToolbarBand, bridgesTrailingDivider: true)
                        .tabBarSpace(model, startsTabBar: true)
                        .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
                } detail: {
                    // On iPad, the trip shows its route as a heading; "Trip Details" adds nothing
                    // above it (iPadOS would also show it when scrolling).
                    JourneyDetailView(showsTitle: Self.detailColumnShowsTitle)
                        .tabBarGap(model)
                        .toolbarBand(model.detailToolbarBand)
                        .tabBarSpace(model, followsDivider: true)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                            model.detailMinX = $0
                        }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 520)
        #else
        // Keep all columns side by side, as on the Mac, instead of sliding the sidebar over them.
        .navigationSplitViewStyle(.balanced)
        #endif
        .onGeometryChange(for: Bool.self) { $0.size.width < Self.compactWidth } action: { compact in
            guard compact != model.isCompact else { return }
            if model.columnVisibility != .all {
                model.columnVisibility = compact ? .detailOnly : .doubleColumn
            }
            model.isCompact = compact
        }
        .feedback(for: model)
        .windowBehavior(model)
    }

    #if os(macOS)
    nonisolated private static let detailColumnShowsTitle = true
    #else
    nonisolated private static let detailColumnShowsTitle = false
    #endif

    private var sidebar: some View {
        SearchView()
            #if os(iOS)
            // Replaced by `JourneysView`, after the full-screen close button (see `AppModel`).
            .toolbar(removing: model.replacesSidebarToggle ? .sidebarToggle : nil)
            #endif
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
    }
}

/// A window showing a single trip, opened from a connection or when the main window is narrow.
struct TripWindow: View {
    @State private var model = AppModel(hasSearch: false)
    #if os(iOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    var journeyID: String?

    var body: some View {
        NavigationStack {
            JourneyDetailView(showsRouteAsTitle: true)
                .toolbarBand(model.detailToolbarBand)
                #if os(iOS)
                // The trip shows the route large itself; keep the window's title small.
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .windowBehavior(model)
        .environment(model)
        .focusedSceneValue(model)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
        .feedback(for: model)
        .onChange(of: journeyID, initial: true) { _, id in
            model.selectedJourney = id.flatMap { model.registry.existing(id: $0) }
            #if os(iOS)
            // iPadOS restores trip windows after a relaunch, but search results aren't kept, so
            // the window would stay empty and could hide the main window.
            if model.selectedJourney == nil {
                dismissWindow()
            }
            #endif
        }
    }
}

extension View {
    /// Room below the toolbar for the iPad's tab bar (`WindowTabBar`), which lies over the
    /// connections and trip columns there, like the Mac's. The columns report where their toolbar
    /// ends, with `startsTabBar` where the bar starts, and with `followsDivider` where the divider
    /// before them is (hidden within the bar and toolbar, as on the Mac). Apply `toolbarBand`
    /// inside this, so the toolbar's band reaches down over the bar. The Mac's native tab bar
    /// needs none of it.
    @ViewBuilder
    func tabBarSpace(_ model: AppModel, startsTabBar: Bool = false, followsDivider: Bool = false) -> some View {
        #if os(iOS)
        safeAreaInset(edge: .top, spacing: 0) {
            if model.tabBarVisible {
                Color.clear.frame(height: WindowTabBar.height)
            }
        }
        // Measured outside the inset, where the column starts right below its toolbar. Passes
        // laying out the column at a token size are skipped.
        .onGeometryChange(for: CGFloat?.self) { proxy in
            proxy.size.height > 2 * WindowTabBar.height
                ? proxy.frame(in: .named(WindowTabBar.coordinateSpace)).minY : nil
        } action: { top in
            if let top { model.tabBarTop = top }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(WindowTabBar.coordinateSpace)).minX } action: {
            if startsTabBar { model.tabBarLeading = $0 }
            if followsDivider { model.tabBarDividerX = $0 }
        }
        #else
        self
        #endif
    }

    /// Space between the iPad's tab bar and the column's content. Apply it inside `toolbarBand`,
    /// so the band (and its divider) still ends right below the bar.
    @ViewBuilder
    func tabBarGap(_ model: AppModel) -> some View {
        #if os(iOS)
        safeAreaPadding(.top, model.tabBarVisible ? 10 : 0)
        #else
        self
        #endif
    }

    /// Draws a band behind the toolbar above this column only.
    ///
    /// SwiftUI's toolbar background APIs affect the whole window's toolbar, so the band is drawn
    /// here instead: opaque in the window colour while tabs show (identical over both columns),
    /// translucent while hovering over the trip details' toolbar.
    ///
    /// - Parameter bridgesTrailingDivider: Extends the band over the gap to the next column while
    ///   tabs show (the divider itself is hidden there by `WindowController`).
    func toolbarBand(_ band: AppModel.ToolbarBand, bridgesTrailingDivider: Bool = false) -> some View {
        modifier(ToolbarBandModifier(band: band, bridgesTrailingDivider: bridgesTrailingDivider))
    }

    /// Toasts and error details of a window.
    func feedback(for model: AppModel) -> some View {
        modifier(FeedbackModifier(model: model))
    }
}

private struct ToolbarBandModifier: ViewModifier {
    var band: AppModel.ToolbarBand
    var bridgesTrailingDivider: Bool
    @State private var topInset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    private var bridges: Bool { bridgesTrailingDivider && band == .tabs }

    func body(content: Content) -> some View {
        content
            // Span the whole column, also when it only shows a placeholder.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
            .overlay(alignment: .top) {
                ZStack {
                    Rectangle().fill(Color.windowBackground)
                        .opacity(band == .tabs || band == .raised ? 1 : 0)
                    Rectangle().fill(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.075))
                        .opacity(band == .raised ? 1 : 0)
                    Rectangle().fill(.bar)
                        .opacity(band == .hover ? 1 : 0)
                }
                .frame(height: topInset)
                // Reach over the split view's divider, which otherwise cuts the bar in two.
                .padding(.trailing, bridges ? -3 : 0)
                .overlay(alignment: .bottom) {
                    Divider()
                        .padding(.trailing, bridges ? -3 : 0)
                        .opacity(band == .none ? 0 : 1)
                }
                .offset(y: -topInset)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.2), value: band)
            }
    }
}

private struct FeedbackModifier: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ToastView(toast: $model.toast)
            }
            .alert(
                "Error",
                isPresented: Binding(get: { model.errorDetails != nil }, set: { if !$0 { model.errorDetails = nil } }),
                presenting: model.errorDetails
            ) { _ in
                Button("Close", role: .cancel) {}
            } message: { details in
                Text(details.message)
            }
    }
}

/// A transient message at the bottom of the window, like libadwaita's toasts.
private struct ToastView: View {
    @Binding var toast: Toast?

    var body: some View {
        ZStack {
            if let current = toast {
                HStack(spacing: 12) {
                    Text(current.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    if let actionTitle = current.actionTitle {
                        Button(actionTitle) {
                            current.action?()
                            dismiss(current)
                        }
                        .buttonStyle(.borderless)
                        .fontWeight(.semibold)
                    }
                    Button {
                        dismiss(current)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss")
                }
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 20)
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: current.id) {
                    guard current.autoDismiss else { return }
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled { dismiss(current) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.spring(duration: 0.35), value: toast)
    }

    private func dismiss(_ current: Toast) {
        guard toast == current else { return }
        current.onDismiss?()
        toast = nil
    }
}
