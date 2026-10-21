import SwiftUI

/// The iOS/iPadOS counterpart of the macOS `NativeSegmentedControl`: a segmented picker filling the
/// available width.
struct NativeSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    var shape: ButtonBorderShape = .capsule

    var body: some View {
        Picker(selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].title).tag(options[index].value)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .buttonBorderShape(shape)
    }
}

/// Station suggestions below the route fields.
///
/// A plain overlay for now; the macOS version uses a separate window instead.
struct SuggestionPanelAnchor: View {
    var field: StationField?
    /// Distance from the top of the anchor to the top of the panel.
    var topOffset: CGFloat
    var anchorFrame: CGRect
    var onSelect: (Place) -> Void

    private static let rowHeight: CGFloat = 44
    private static let maximumHeight: CGFloat = 330

    var body: some View {
        if let field, !field.suggestions.isEmpty, !field.isSet {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(field.suggestions.enumerated()), id: \.offset) { _, place in
                        Button {
                            onSelect(place)
                        } label: {
                            Text(place.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                                .padding(.horizontal, 16)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(CGFloat(field.suggestions.count) * Self.rowHeight, Self.maximumHeight))
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .offset(y: topOffset)
            .accessibilityLabel("Suggestions")
        }
    }
}

extension View {
    /// macOS window behaviour (tabs, toolbar hover); windows on iOS/iPadOS need none of it.
    func windowBehavior(_ model: AppModel) -> some View {
        self
    }
}
