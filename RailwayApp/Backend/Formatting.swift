import Foundation

/// Text formatting shared across the app, ported from Railway's `utility.rs`.
enum Format {
    /// `12:34` in the user's time zone.
    static func time(_ time: ZonedTime?) -> String? {
        time.map { Self.time($0.date) }
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits))
    }

    /// Duration in a compact, table-friendly form, e.g. `45 min` or `2 h 05 min`.
    static func durationTabular(_ duration: Duration) -> String {
        let minutes = Int(duration.components.seconds / 60)
        let days = minutes / (60 * 24)
        let hours = minutes / 60 % 24
        let rest = minutes % 60
        if minutes < 60 {
            return String(localized: "\(minutes) min")
        } else if days == 0 {
            return String(localized: "\(hours) h \(rest) min")
        } else {
            return String(localized: "\(days) d \(hours) h \(rest) min")
        }
    }

    /// Duration embedded in running text, e.g. `5 min.` or `2 hrs. 5 min.`.
    static func durationInline(_ duration: Duration) -> String {
        let minutes = Int(duration.components.seconds / 60)
        let days = minutes / (60 * 24)
        let hours = minutes / 60 % 24
        let rest = minutes % 60
        if minutes < 120 {
            return String(localized: "\(minutes) min.")
        } else if days == 0 {
            return rest == 0
                ? String(localized: "\(hours) hrs.")
                : String(localized: "\(hours) hrs. \(rest) min.")
        } else {
            return String(localized: "\(days) days \(hours) hrs. \(rest) min.")
        }
    }

    /// `Today`, `Tomorrow`, `Yesterday`, `Tue, 21. October` or `2027-01-01`.
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
        }
        return date.formatted(.iso8601.year().month().day())
    }

    static func price(_ price: Price) -> String {
        price.amount.formatted(.currency(code: price.currency))
    }
}

/// How late something is, ported from Railway's `late_factor.rs`.
enum LateFactor: Int, Comparable {
    case onTime, littleLate, late, veryLate, extremelyLate

    init(real: ZonedTime?, planned: ZonedTime?) {
        guard let real, let planned else {
            self = .onTime
            return
        }
        let minutes = Int(real.date.timeIntervalSince(planned.date) / 60)
        self = switch minutes {
        case ...0: .onTime
        case 1..<5: .littleLate
        case 5..<15: .late
        case 15..<60: .veryLate
        default: .extremelyLate
        }
    }

    static func < (lhs: LateFactor, rhs: LateFactor) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension ZonedTime {
    static func - (lhs: ZonedTime, rhs: ZonedTime) -> Duration {
        .seconds(lhs.date.timeIntervalSince(rhs.date))
    }
}

extension Duration {
    var minutes: Int { Int(components.seconds / 60) }
}

extension Leg {
    /// An identifier based on attributes that do not change when refreshed.
    var stableID: String {
        [
            tripId ?? "",
            plannedDeparture.map { "\($0.date.timeIntervalSince1970)" } ?? "",
            plannedArrival.map { "\($0.date.timeIntervalSince1970)" } ?? "",
            plannedDeparturePlatform ?? "",
            plannedArrivalPlatform ?? "",
        ].joined(separator: ";")
    }

    /// The name of the line, e.g. `ICE 1605`, or the mode of transport.
    var displayName: String {
        if walking { return String(localized: "Walk") }
        return line?.name ?? line?.productName ?? line?.product.name ?? String(localized: "Unknown")
    }

    var mode: Mode { line?.mode == .unknown ? line?.product.mode ?? .unknown : line?.mode ?? .unknown }

    var lateFactor: LateFactor {
        max(
            LateFactor(real: arrival, planned: plannedArrival),
            LateFactor(real: departure, planned: plannedDeparture)
        )
    }

    var changesPlatform: Bool {
        departurePlatform != plannedDeparturePlatform || arrivalPlatform != plannedArrivalPlatform
    }

    /// Stops between origin and destination (the first and last stop are the leg's ends).
    var intermediateStops: [IntermediateLocation] {
        guard intermediateLocations.count > 2 else { return [] }
        return Array(intermediateLocations.dropFirst().dropLast())
    }

    var stopCount: Int {
        intermediateStops.count { if case .stop = $0 { true } else { false } }
    }

    var averageFrequency: Duration? {
        guard let frequency else { return nil }
        switch (frequency.minimum, frequency.maximum) {
        case let (min?, max?): return .seconds((min.value + max.value) / 2 * 60)
        case let (value?, nil), let (nil, value?): return value.duration
        default: return nil
        }
    }
}

extension Journey {
    var firstLeg: Leg? { legs.first }
    var lastLeg: Leg? { legs.last }

    var departure: ZonedTime? { firstLeg?.departure ?? firstLeg?.plannedDeparture }
    var arrival: ZonedTime? { lastLeg?.arrival ?? lastLeg?.plannedArrival }

    var totalTime: Duration? {
        guard let departure = firstLeg?.departure, let arrival = lastLeg?.arrival else { return nil }
        return arrival - departure
    }

    /// Number of changes between vehicles.
    var transitions: Int { max(legs.count { !$0.walking } - 1, 0) }

    /// The products used, e.g. `ICE • RE • Bus`.
    var types: String {
        legs.compactMap { $0.line.map { $0.productName ?? $0.product.name } }.joined(separator: " • ")
    }

    var loadFactor: LoadFactor? { legs.compactMap(\.loadFactor).max() }
    var lateFactor: LateFactor { legs.map(\.lateFactor).max() ?? .onTime }
    var changesPlatform: Bool { legs.contains(where: \.changesPlatform) }
    var isUnreachable: Bool { legs.contains { !$0.reachable } }
    var isCancelled: Bool { legs.contains(where: \.cancelled) }

    var originName: String { firstLeg?.origin.name ?? "" }
    var destinationName: String { lastLeg?.destination.name ?? "" }
}
