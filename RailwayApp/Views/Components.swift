import SwiftUI

/// A scheduled time together with the real-time estimate, ported from Railway's `AltLabel`.
///
/// On time: just the planned time. Delayed: the planned time struck through next to the new time.
struct TimeLabel: View {
    enum Style { case prominent, regular, small }

    var planned: ZonedTime?
    var real: ZonedTime?
    var style = Style.regular
    var axis = Axis.horizontal
    @Environment(\.backgroundProminence) private var prominence

    /// Delays are red, except on a selected row where everything is white.
    private var delayStyle: AnyShapeStyle {
        prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.red)
    }

    private var isDifferent: Bool {
        planned != nil && real != nil && planned != real
    }

    private var mainFont: Font {
        switch style {
        case .prominent: .title3.weight(.semibold).monospacedDigit()
        case .regular: .body.weight(.semibold).monospacedDigit()
        case .small: .callout.monospacedDigit()
        }
    }

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 0))
        layout {
            if isDifferent, let planned = Format.time(planned), let real = Format.time(real) {
                if axis == .vertical {
                    Text(real).font(mainFont).foregroundStyle(delayStyle)
                    Text(planned).font(.caption.monospacedDigit()).strikethrough().foregroundStyle(.secondary)
                } else {
                    Text(planned).font(.caption.monospacedDigit()).strikethrough().foregroundStyle(.secondary)
                    Text(real).font(mainFont).foregroundStyle(delayStyle)
                }
            } else if let time = Format.time(planned ?? real) {
                Text(time).font(mainFont)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        if isDifferent, let planned = Format.time(planned), let real = Format.time(real) {
            Text("\(real), planned \(planned)")
        } else {
            Text(Format.time(planned ?? real) ?? "")
        }
    }
}

/// A platform number; changed platforms show the new one highlighted.
struct PlatformLabel: View {
    var planned: String?
    var real: String?

    var body: some View {
        let changed = planned != nil && real != nil && planned != real
        if let platform = real ?? planned {
            HStack(spacing: 4) {
                if changed, let planned {
                    Text(planned).strikethrough().foregroundStyle(.secondary)
                }
                Text(platform)
                    .foregroundStyle(changed ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background {
                        if changed {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.orange)
                        } else {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.tertiary)
                        }
                    }
            }
            .font(.callout.monospacedDigit())
            .help(changed ? Text("Platform changed from \(planned ?? "") to \(platform)") : Text("Platform \(platform)"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Platform \(platform)"))
        }
    }
}

extension Mode {
    var systemImage: String {
        switch self {
        case .highSpeedTrain: "train.side.front.car"
        case .regionalTrain: "train.side.rear.car"
        case .suburbanTrain: "lightrail"
        case .subway: "tram.fill.tunnel"
        case .tram: "tram"
        case .bus: "bus"
        case .ferry: "ferry"
        case .cablecar: "cablecar"
        case .onDemand: "car"
        case .unknown: "train.side.front.car"
        }
    }

    var tint: Color {
        switch self {
        case .highSpeedTrain: .red
        case .regionalTrain: .indigo
        case .suburbanTrain: .green
        case .subway: .blue
        case .tram: .orange
        case .bus: .purple
        case .ferry: .cyan
        case .cablecar: .brown
        case .onDemand: .yellow
        case .unknown: .gray
        }
    }
}

extension Leg {
    /// The mode, guessed from the product name if the provider does not report it.
    var inferredMode: Mode {
        // Some providers report buses as trains.
        if [line?.productName, line?.name].contains(where: { $0?.uppercased().hasPrefix("BUS") == true }) {
            return .bus
        }
        if mode != .unknown { return mode }
        let product = (line?.productName ?? line?.name ?? "").uppercased()
        let prefix = product.split(separator: " ").first.map(String.init) ?? product
        switch prefix {
        case "ICE", "IC", "EC", "ECE", "TGV", "RJ", "RJX", "NJ", "EN", "FLX", "WB", "EST", "IR": return .highSpeedTrain
        case "RE", "RB", "IRE", "R", "REX", "MEX", "TER": return .regionalTrain
        case "S", "SB": return .suburbanTrain
        case "U", "M": return .subway
        case "STR", "TRAM", "T": return .tram
        case "BUS", "B", "RUF", "AST": return .bus
        case "F", "FÄHRE", "SCH": return .ferry
        default:
            if prefix.hasPrefix("S") && prefix.dropFirst().allSatisfy(\.isNumber) { return .suburbanTrain }
            if prefix.hasPrefix("U") && prefix.dropFirst().allSatisfy(\.isNumber) { return .subway }
            return .unknown
        }
    }
}

/// The line serving a leg as a coloured capsule, e.g. "🚆 ICE 1605".
struct LineBadge: View {
    var leg: Leg

    var body: some View {
        let mode = leg.inferredMode
        Label(leg.displayName, systemImage: mode.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(mode.tint.gradient, in: .capsule)
            .fixedSize()
    }
}

/// Small status icons, ported from Railway's `IndicatorIcons`.
struct IndicatorIcons: View {
    var loadFactor: LoadFactor?
    var lateFactor: LateFactor
    var changesPlatform: Bool
    var isUnreachable: Bool
    var isCancelled: Bool
    @Environment(\.backgroundProminence) private var prominence

    init(journey: Journey) {
        loadFactor = journey.loadFactor
        lateFactor = journey.lateFactor
        changesPlatform = journey.changesPlatform
        isUnreachable = journey.isUnreachable
        isCancelled = journey.isCancelled
    }

    init(leg: Leg) {
        loadFactor = leg.loadFactor
        lateFactor = leg.lateFactor
        changesPlatform = leg.changesPlatform
        isUnreachable = !leg.reachable
        isCancelled = leg.cancelled
    }

    private struct Indicator: Identifiable {
        var id: String { symbol }
        var symbol: String
        var color: Color
        var help: LocalizedStringKey
    }

    private var indicators: [Indicator] {
        var result: [Indicator] = []
        switch loadFactor {
        case .high: result.append(.init(symbol: "person.2.fill", color: .orange, help: "High Load"))
        case .veryHigh: result.append(.init(symbol: "person.3.fill", color: .red, help: "Very High Load"))
        case .exceptionallyHigh: result.append(.init(symbol: "person.3.sequence.fill", color: .red, help: "Exceptionally High Load"))
        case .lowToMedium, nil: break
        }
        switch lateFactor {
        case .littleLate: result.append(.init(symbol: "clock.fill", color: .yellow, help: "Minor Delays"))
        case .late: result.append(.init(symbol: "clock.badge.exclamationmark.fill", color: .orange, help: "Delayed"))
        case .veryLate: result.append(.init(symbol: "clock.badge.exclamationmark.fill", color: .red, help: "Very Delayed"))
        case .extremelyLate: result.append(.init(symbol: "exclamationmark.octagon.fill", color: .red, help: "Extremely Delayed"))
        case .onTime: break
        }
        if changesPlatform {
            result.append(.init(symbol: "arrow.left.arrow.right.square.fill", color: .orange, help: "Platform Changes"))
        }
        if isUnreachable {
            result.append(.init(symbol: "exclamationmark.triangle.fill", color: .red, help: "Connection Not Possible"))
        }
        if isCancelled {
            result.append(.init(symbol: "xmark.octagon.fill", color: .red, help: "Cancelled"))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(indicators) { indicator in
                Image(systemName: indicator.symbol)
                    .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(indicator.color))
                    .help(indicator.help)
                    .accessibilityLabel(indicator.help)
            }
        }
        .imageScale(.small)
    }
}

extension RemarkAssociation {
    var systemImage: String {
        switch self {
        case .bike: "bicycle"
        case .accessibility: "figure.roll"
        case .ticket: "ticket"
        case .power: "powerplug"
        case .airConditioning: "thermometer.snowflake"
        case .wifi: "wifi"
        case .onlySecondClass: "2.circle"
        case .unknown, .none: "info.circle"
        }
    }
}

/// The logo of a network.
struct ProviderIcon: View {
    var provider: Provider
    var size: CGFloat = 22

    var body: some View {
        Image(provider.iconName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A rounded container used for the cards in the sidebar and trip details.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            }
    }
}

extension View {
    func card(cornerRadius: CGFloat = 14) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}
