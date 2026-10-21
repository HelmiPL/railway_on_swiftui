import SwiftUI

/// The tabs of one window. On the Mac, every tab is a window of its own in a native tab group;
/// iPadOS has no window tabs, so a window holds its tabs itself, each with its own search.
@Observable
final class WindowTabs {
    struct Tab: Identifiable {
        let id = UUID()
        let model: AppModel
    }

    private(set) var tabs: [Tab]
    private(set) var selectedID: Tab.ID

    init() {
        let first = Tab(model: AppModel())
        tabs = [first]
        selectedID = first.id
    }

    var selected: Tab {
        tabs.first { $0.id == selectedID } ?? tabs[0]
    }

    private var selectedIndex: Int {
        tabs.firstIndex { $0.id == selectedID } ?? 0
    }

    /// Like ⌘T on the Mac: a new tab after the current one, with the last search filled in.
    func newTab() {
        let tab = Tab(model: AppModel())
        tabs.insert(tab, at: selectedIndex + 1)
        selectedID = tab.id
    }

    func select(_ tab: Tab) {
        selectedID = tab.id
    }

    /// ⌘1–⌘8 select a tab by position, ⌘9 the last one.
    func select(number: Int) {
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        selectedID = tabs[index].id
    }

    func selectNext() {
        selectedID = tabs[(selectedIndex + 1) % tabs.count].id
    }

    func selectPrevious() {
        selectedID = tabs[(selectedIndex - 1 + tabs.count) % tabs.count].id
    }

    var canClose: Bool { tabs.count > 1 }

    /// Closing the current tab selects the one after it, or the one before if it was the last.
    func close(_ tab: Tab) {
        guard canClose, let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.model.saveSearchInputs()
        tabs.remove(at: index)
        if tab.id == selectedID {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeSelected() {
        close(selected)
    }
}

/// The tab bar in the toolbar, drawn like the Mac's: equal tabs named after their search, the
/// current one raised, a close button on hover and "+" at the end. The columns' toolbar band
/// (see `toolbarBand`) reaches down behind it, so toolbar and tabs read as one.
struct WindowTabBar: View {
    var tabs: WindowTabs

    static let height: CGFloat = 40
    /// The window's content, where the columns measure their toolbars and the bar is placed.
    nonisolated static let coordinateSpace = "window-tabs"

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(tabs.tabs) { tab in
                    WindowTabItem(
                        model: tab.model,
                        isSelected: tab.id == tabs.selectedID,
                        canClose: tabs.canClose,
                        onSelect: { tabs.select(tab) },
                        onClose: { withAnimation(.snappy) { tabs.close(tab) } }
                    )
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.06), in: .capsule)

            Button {
                withAnimation(.snappy) { tabs.newTab() }
            } label: {
                Image(systemName: "plus")
                    .font(.callout.weight(.medium))
                    .frame(width: 30, height: 30)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .hoverEffect(.highlight)
            .accessibilityLabel("New Tab")
        }
        .padding(.horizontal, 10)
        // The tabs (34 pt) sit in the bar's upper part, clear of its top edge.
        .padding(.bottom, 4)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // The colour of the toolbar's band around it; it also hides the columns' divider.
        .background(Color.windowBackground)
    }
}

private struct WindowTabItem: View {
    var model: AppModel
    var isSelected: Bool
    var canClose: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    @State private var hovering = false

    /// The Mac names a tab after its window: the route searched for, or the app.
    private var title: String {
        model.result.map { "\($0.source.name) → \($0.destination.name)" } ?? String(localized: "Railway")
    }

    var body: some View {
        Text(title)
            .font(.callout.weight(isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            // Room for the close button on both sides, so the title stays centred.
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background {
                if isSelected {
                    Capsule().fill(Color.windowBackground)
                        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                } else if hovering {
                    Capsule().fill(Color.primary.opacity(0.06))
                }
            }
            .overlay(alignment: .leading) {
                // On hover like on the Mac; always on the current tab, for touch.
                if canClose, hovering || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .padding(.leading, 4)
                    .accessibilityLabel("Close Tab")
                }
            }
            .contentShape(.capsule)
            .onTapGesture(perform: onSelect)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onSelect)
    }
}
