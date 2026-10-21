import SwiftUI

/// The main window: search, connections and trip details side by side, like Railway's split views.
///
/// When the window is too narrow for three columns, trips open in their own windows instead.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    /// Below this width the trip details move to separate windows.
    nonisolated private static let compactWidth: CGFloat = 1000

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isCompact {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    sidebar
                } detail: {
                    JourneysView()
                }
            } else {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    sidebar
                } content: {
                    JourneysView()
                        .toolbarBand(model.contentToolbarBand, bridgesTrailingDivider: true)
                        .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 480)
                } detail: {
                    JourneyDetailView()
                        .toolbarBand(model.detailToolbarBand)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                            model.detailMinX = $0
                        }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
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

    private var sidebar: some View {
        SearchView()
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
    }
}

/// A window showing a single trip, opened from a connection or when the main window is narrow.
struct TripWindow: View {
    @State private var model = AppModel(hasSearch: false)
    var journeyID: String?

    var body: some View {
        NavigationStack {
            JourneyDetailView(showsRouteAsTitle: true)
                .toolbarBand(model.detailToolbarBand)
        }
        .windowBehavior(model)
        .environment(model)
        .focusedSceneValue(model)
        .frame(minWidth: 420, minHeight: 420)
        .feedback(for: model)
        .onChange(of: journeyID, initial: true) { _, id in
            model.selectedJourney = id.flatMap { model.registry.existing(id: $0) }
        }
    }
}

extension View {
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
                    Rectangle().fill(Color(nsColor: .windowBackgroundColor))
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
