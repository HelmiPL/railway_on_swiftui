import AppKit
import SwiftUI

/// The system segmented control with the macOS 27 "tabs" role: native Liquid Glass styling with a
/// neutral thumb, segments filling the available width.
struct NativeSegmentedControl<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    /// `.capsule` for the rounded look, `.roundedRectangle` for the more angular one.
    var shape: NSControl.BorderShape = .capsule

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.role = .tabs
        control.controlSize = .large
        control.borderShape = shape
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if let index = options.firstIndex(where: { $0.value == selection }), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        // Take the offered width; keep the control's own height.
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: NativeSegmentedControl

        init(parent: NativeSegmentedControl) {
            self.parent = parent
        }

        @objc func changed(_ control: NSSegmentedControl) {
            guard parent.options.indices.contains(control.selectedSegment) else { return }
            parent.selection = parent.options[control.selectedSegment].value
        }
    }
}
