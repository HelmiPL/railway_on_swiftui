import AppKit
import SwiftUI

/// Shows station suggestions in a borderless child window below the route fields.
///
/// A separate window is what system suggestion menus use: it gets the regular popover glass,
/// which adapts to light and dark mode and samples whatever lies behind it, and it never takes
/// keyboard focus away from the text field being typed in.
struct SuggestionPanelAnchor: NSViewRepresentable {
    var field: StationField?
    /// Distance from the top of the anchor to the top of the panel.
    var topOffset: CGFloat
    /// Changes whenever the anchor moves, so the panel follows.
    var anchorFrame: CGRect
    var onSelect: (Place) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let controller = context.coordinator
        guard let field, !field.suggestions.isEmpty, !field.isSet else {
            controller.hide()
            return
        }
        // The anchor may not be in a window yet during the first update.
        DispatchQueue.main.async {
            controller.show(field: field, below: view, topOffset: topOffset, onSelect: onSelect)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: SuggestionPanelController) {
        coordinator.hide()
    }

    func makeCoordinator() -> SuggestionPanelController {
        SuggestionPanelController()
    }
}

@MainActor
final class SuggestionPanelController {
    private var panel: NSPanel?
    private var host: FirstMouseHostingView<AnyView>?
    private weak var field: StationField?

    static let rowHeight: CGFloat = 24
    static let padding: CGFloat = 5
    static let maximumHeight: CGFloat = 330

    func show(field: StationField, below anchor: NSView, topOffset: CGFloat, onSelect: @escaping (Place) -> Void) {
        guard let parent = anchor.window, !field.suggestions.isEmpty, !field.isSet else {
            hide()
            return
        }
        let panel = panel ?? makePanel()
        if self.field !== field || host == nil {
            self.field = field
            let content = AnyView(SuggestionMenu(field: field, onSelect: onSelect))
            if let host {
                host.rootView = content
            } else {
                let host = FirstMouseHostingView(rootView: content)
                panel.contentView = host
                self.host = host
            }
        }

        let anchorRect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let height = min(
            CGFloat(field.suggestions.count) * Self.rowHeight + 2 * Self.padding,
            Self.maximumHeight
        )
        let frame = CGRect(
            x: anchorRect.minX,
            y: anchorRect.maxY - topOffset - height,
            width: anchorRect.width,
            height: height
        )
        panel.setFrame(frame, display: true)
        if panel.parent == nil {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setAccessibilityRole(.popover)
        self.panel = panel
        return panel
    }
}

/// Lets clicks select a suggestion even though the panel never becomes the key window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The suggestions, styled like a menu: compact rows highlighted in the accent colour.
private struct SuggestionMenu: View {
    var field: StationField
    var onSelect: (Place) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(field.suggestions.enumerated()), id: \.offset) { index, place in
                    SuggestionRow(place: place, isHighlighted: field.highlighted == index)
                        .onHover { hovering in
                            if hovering { field.highlighted = index }
                        }
                        .onTapGesture { onSelect(place) }
                }
            }
            .padding(SuggestionPanelController.padding)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }
}

private struct SuggestionRow: View {
    var place: Place
    var isHighlighted: Bool

    private var kind: (symbol: String, label: LocalizedStringKey) {
        switch place {
        case .station: ("tram.fill", "Station")
        case .location(.address): ("house.fill", "Address")
        case .location(.point(_, _, true, _, _)): ("star.fill", "Point of Interest")
        case .location(.point): ("mappin", "Place")
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .frame(width: 16)
            Text(place.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(kind.label)
                .font(.caption)
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        }
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: SuggestionPanelController.rowHeight)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }
}
