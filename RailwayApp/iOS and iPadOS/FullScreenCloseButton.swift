import SwiftUI
import UIKit

/// The red close button of the window controls, for full screen, where iPadOS hides the real
/// ones until the pointer reaches the corner. Minimising and leaving full screen have no public
/// API, so only closing is offered.
///
/// Sizes and colour are measured from the system's controls in a windowed scene: a glass capsule
/// 21.5 pt high with 5.5 pt dots, which grow (to 20.3 pt in a 35.5 pt capsule) and show their
/// symbol on hover. They are rounded to even sizes here: every frame is centred in the next, and
/// half points would be rounded to the pixel grid differently for the circle and the ×, leaving
/// them half a point apart.
struct FullScreenCloseButton: View {
    var close: () -> Void
    @State private var hovering = false
    /// The pointer is on the red circle itself, not just on the expanded controls.
    @State private var hoveringDot = false

    static let size: CGFloat = 22
    private static let dotSize: CGFloat = 6
    /// Measured from the expanded controls: 20 pt dots with 8 pt of glass around them.
    static let hoverSize: CGFloat = 36
    private static let hoverDotSize: CGFloat = 20
    /// With the pointer on it, the circle grows once more.
    private static let pointedDotSize: CGFloat = 24

    private var dotSize: CGFloat {
        hovering ? (hoveringDot ? Self.pointedDotSize : Self.hoverDotSize) : Self.dotSize
    }
    /// The left edge of the system's controls, as far from the window's edge as from its top.
    static let leading: CGFloat = 21
    private static let red = Color(red: 224 / 255, green: 115 / 255, blue: 102 / 255)
    /// Expanded, the controls are fully saturated.
    private static let hoverRed = Color(red: 255 / 255, green: 11 / 255, blue: 24 / 255)

    var body: some View {
        Button(action: close) {
            ZStack {
                Circle()
                    .fill(hovering ? Self.hoverRed : Self.red)
                    .frame(width: dotSize, height: dotSize)
                    .onHover { over in
                        withAnimation(.snappy(duration: 0.15)) { hoveringDot = over }
                    }
                if hovering {
                    // Drawn rather than the `xmark` symbol, whose image has uneven padding and sits a
                    // quarter point off the circle's centre.
                    Cross()
                        .stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: hoveringDot ? 2 : 1.7, lineCap: .round))
                        // Even sizes, so the frame starts on whole pixels and isn't shifted to them.
                        .frame(width: hoveringDot ? 10 : 8, height: hoveringDot ? 10 : 8)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            // Grown by its size rather than scaled: the glass is drawn separately and wouldn't
            // stay centred under a scaled dot.
            .frame(width: hovering ? Self.hoverSize : Self.size, height: hovering ? Self.hoverSize : Self.size)
            .glassEffect(.regular, in: .capsule)
            // A larger target for touch than the small capsule; it keeps the button's size the
            // same while the capsule grows, so the capsule grows around its centre.
            .frame(width: Self.hoverSize + 16, height: Self.hoverSize + 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The pointer's default lift effect shifts the content towards the pointer, moving the
        // dot off the capsule's centre; the system's controls only grow.
        .hoverEffectDisabled()
        .onHover { over in
            withAnimation(.snappy(duration: 0.2)) {
                hovering = over
                if !over { hoveringDot = false }
            }
        }
        .accessibilityLabel("Close Window")
        #if DEBUG
        .task {
            // `RAILWAY_HOVER_CLOSE=1`: hover after a second, which the simulator can't do.
            guard ProcessInfo.processInfo.environment["RAILWAY_HOVER_CLOSE"] != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.snappy(duration: 0.2)) { hovering = true }
            // `RAILWAY_HOVER_CLOSE=dot`: then move onto the red circle.
            if ProcessInfo.processInfo.environment["RAILWAY_HOVER_CLOSE"] == "dot" {
                try? await Task.sleep(for: .seconds(1))
                withAnimation(.snappy(duration: 0.15)) { hoveringDot = true }
            }
        }
        #endif
    }
}

/// Reports the window's scene and whether the window fills the screen, whenever it is resized.
struct WindowObserver: UIViewRepresentable {
    var onChange: (UIWindowScene, _ isFullScreen: Bool) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: UIView {
        var onChange: ((UIWindowScene, Bool) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        /// iOS has no full screen state for scenes (only Mac Catalyst does): a window as large as
        /// its screen is taken as full screen.
        private func report() {
            guard let window, let scene = window.windowScene else { return }
            let screen = scene.screen.bounds.size
            let size = window.bounds.size
            let isFullScreen = abs(size.width - screen.width) < 1 && abs(size.height - screen.height) < 1
            DispatchQueue.main.async { [onChange] in onChange?(scene, isFullScreen) }
        }
    }
}

/// An × from corner to corner of its frame.
nonisolated private struct Cross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
