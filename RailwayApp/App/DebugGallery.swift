#if DEBUG
import AppKit
import SwiftUI

/// Compares segmented control variants in a real window (glass only renders there).
/// Opened with `RAILWAY_GALLERY=1`.
enum DebugGallery {
    static func open() {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 760, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Segmented Gallery"
        window.contentView = NSHostingView(rootView: GalleryView())
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
    }
}

private struct GalleryView: View {
    @State private var value = 0

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            column(onGlass: false)
            column(onGlass: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(onGlass: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(onGlass ? "On glass" : "Plain").font(.headline)
            labelled("1 SwiftUI regular") { picker.controlSize(.regular) }
            labelled("2 SwiftUI large") { picker.controlSize(.large) }
            labelled("3 SwiftUI extraLarge") { picker.controlSize(.extraLarge) }
            labelled("4 AppKit role tabs, large") { AppKitSegmented(role: .tabs, size: .large) }
            labelled("5 AppKit role tabs, extraLarge") { AppKitSegmented(role: .tabs, size: .extraLarge) }
            labelled("6 AppKit role tabs, capsule, fill equally") { AppKitSegmented(role: .tabs, size: .large, shape: .capsule) }
            labelled("7 AppKit role valueSelection") { AppKitSegmented(role: .valueSelection, size: .large) }
        }
        .padding(14)
        .background {
            if onGlass {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
    }

    private var picker: some View {
        Picker("Type", selection: $value) {
            Text("Departure").tag(0)
            Text("Arrival").tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func labelled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

private struct AppKitSegmented: NSViewRepresentable {
    var role: NSSegmentedControl.Role
    var size: NSControl.ControlSize
    var shape: NSControl.BorderShape = .automatic

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["Departure", "Arrival"], trackingMode: .selectOne, target: nil, action: nil)
        control.role = role
        control.controlSize = size
        control.borderShape = shape
        control.segmentDistribution = .fillEqually
        control.selectedSegment = 0
        return control
    }

    func updateNSView(_ view: NSSegmentedControl, context: Context) {}
}
#endif
