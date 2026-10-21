import Foundation

// Swift mirrors of the `railway-core` types, matching their serde JSON representation exactly so
// journeys can be round-tripped back to the backend (refreshing) and persisted (bookmarks).
//
// Notes on the encoding:
// - Rust enums are externally tagged: `{"Station": {...}}`.
// - Date-times are `["<naive UTC date-time>", "<IANA time zone>"]`.
// - Durations (frequency) are whole minutes.

// MARK: - Date-time

/// A point in time together with the time zone the provider reported it in.
nonisolated struct ZonedTime: Codable, Hashable, Comparable, Sendable {
    var date: Date
    var timeZone: String

    init(date: Date, timeZone: String) {
        self.date = date
        self.timeZone = timeZone
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let naive = try container.decode(String.self)
        timeZone = try container.decode(String.self)
        guard let date = Self.parse(naive) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date-time \(naive)")
        }
        self.date = date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(date.formatted(Self.style))
        try container.encode(timeZone)
    }

    static func < (lhs: ZonedTime, rhs: ZonedTime) -> Bool { lhs.date < rhs.date }

    private static let style = Date.ISO8601FormatStyle(timeZone: .gmt)
        .year().month().day().dateTimeSeparator(.standard).time(includingFractionalSeconds: false)

    private static func parse(_ string: String) -> Date? {
        // chrono writes fractional seconds only when present; drop them, providers use minutes anyway.
        let trimmed = string.split(separator: ".").first.map(String.init) ?? string
        return try? style.parse(trimmed)
    }
}

/// An optional value that is encoded as an explicit `null` instead of being omitted.
///
/// Fields that use a custom `serde(with = ...)` in Rust do not accept missing keys.
nonisolated struct Nullable<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var value: Value?

    init(_ value: Value?) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = container.decodeNil() ? nil : try container.decode(Value.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) } else { try container.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    nonisolated func decode<Value>(_ type: Nullable<Value>.Type, forKey key: Key) throws -> Nullable<Value> {
        try decodeIfPresent(type, forKey: key) ?? Nullable(nil)
    }
}

/// Whole minutes, as used by `railway-core` for durations.
nonisolated struct Minutes: Codable, Hashable, Sendable {
    var value: Int

    init(from decoder: Decoder) throws { value = try decoder.singleValueContainer().decode(Int.self) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    var duration: Duration { .seconds(value * 60) }
}

// MARK: - Places

nonisolated enum Location: Codable, Hashable, Sendable {
    case address(address: String, latitude: Double, longitude: Double)
    case point(id: String?, name: String?, poi: Bool?, latitude: Double, longitude: Double)

    private enum Tag: String, CodingKey { case Address, Point }
    private enum Keys: String, CodingKey { case address, id, name, poi, latitude, longitude }

    init(from decoder: Decoder) throws {
        let tagged = try decoder.container(keyedBy: Tag.self)
        if tagged.contains(.Address) {
            let c = try tagged.nestedContainer(keyedBy: Keys.self, forKey: .Address)
            self = .address(
                address: try c.decode(String.self, forKey: .address),
                latitude: try c.decode(Double.self, forKey: .latitude),
                longitude: try c.decode(Double.self, forKey: .longitude)
            )
        } else {
            let c = try tagged.nestedContainer(keyedBy: Keys.self, forKey: .Point)
            self = .point(
                id: try c.decodeIfPresent(String.self, forKey: .id),
                name: try c.decodeIfPresent(String.self, forKey: .name),
                poi: try c.decodeIfPresent(Bool.self, forKey: .poi),
                latitude: try c.decode(Double.self, forKey: .latitude),
                longitude: try c.decode(Double.self, forKey: .longitude)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var tagged = encoder.container(keyedBy: Tag.self)
        switch self {
        case let .address(address, latitude, longitude):
            var c = tagged.nestedContainer(keyedBy: Keys.self, forKey: .Address)
            try c.encode(address, forKey: .address)
            try c.encode(latitude, forKey: .latitude)
            try c.encode(longitude, forKey: .longitude)
        case let .point(id, name, poi, latitude, longitude):
            var c = tagged.nestedContainer(keyedBy: Keys.self, forKey: .Point)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(poi, forKey: .poi)
            try c.encode(latitude, forKey: .latitude)
            try c.encode(longitude, forKey: .longitude)
        }
    }
}

nonisolated struct Station: Codable, Hashable, Sendable {
    var id: String
    var name: String?
    var location: Location?
    var products: [Product]
}

nonisolated enum Place: Codable, Hashable, Sendable {
    case station(Station)
    case location(Location)

    private enum Tag: String, CodingKey { case Station, Location }

    init(from decoder: Decoder) throws {
        let tagged = try decoder.container(keyedBy: Tag.self)
        if tagged.contains(.Station) {
            self = .station(try tagged.decode(Station.self, forKey: .Station))
        } else {
            self = .location(try tagged.decode(Location.self, forKey: .Location))
        }
    }

    func encode(to encoder: Encoder) throws {
        var tagged = encoder.container(keyedBy: Tag.self)
        switch self {
        case let .station(station): try tagged.encode(station, forKey: .Station)
        case let .location(location): try tagged.encode(location, forKey: .Location)
        }
    }

    var name: String {
        switch self {
        case let .station(station): station.name ?? station.id
        case let .location(.address(address, _, _)): address
        case let .location(.point(id, name, _, _, _)): name ?? id ?? ""
        }
    }

    var id: String? {
        switch self {
        case let .station(station): station.id
        case .location(.address): nil
        case let .location(.point(id, _, _, _, _)): id
        }
    }

    /// Whether the place is a point of interest or address rather than a stop.
    var isStation: Bool {
        if case .station = self { true } else { false }
    }
}

// MARK: - Lines and products

nonisolated enum Mode: String, Codable, Hashable, Sendable, CaseIterable {
    case highSpeedTrain = "HighSpeedTrain"
    case regionalTrain = "RegionalTrain"
    case suburbanTrain = "SuburbanTrain"
    case subway = "Subway"
    case tram = "Tram"
    case bus = "Bus"
    case ferry = "Ferry"
    case cablecar = "Cablecar"
    case onDemand = "OnDemand"
    case unknown = "Unknown"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Mode(rawValue: raw) ?? .unknown
    }
}

nonisolated struct Product: Codable, Hashable, Sendable {
    var mode: Mode
    var name: String
    var short: String
}

nonisolated struct Operator: Codable, Hashable, Sendable {
    var id: String
    var name: String
}

nonisolated struct Line: Codable, Hashable, Sendable {
    var name: String?
    var fahrtNr: String?
    var mode: Mode
    var product: Product
    var `operator`: Operator?
    var productName: String?

    enum CodingKeys: String, CodingKey {
        case name, mode, product, `operator`
        case fahrtNr = "fahrt_nr"
        case productName = "product_name"
    }
}

nonisolated struct Frequency: Codable, Hashable, Sendable {
    private var _minimum: Nullable<Minutes>
    private var _maximum: Nullable<Minutes>
    var iterations: UInt64?

    enum CodingKeys: String, CodingKey {
        case iterations
        case _minimum = "minimum"
        case _maximum = "maximum"
    }

    var minimum: Minutes? {
        get { _minimum.value }
        set { _minimum = Nullable(newValue) }
    }

    var maximum: Minutes? {
        get { _maximum.value }
        set { _maximum = Nullable(newValue) }
    }
}

nonisolated enum LoadFactor: String, Codable, Hashable, Sendable, Comparable {
    case lowToMedium = "LowToMedium"
    case high = "High"
    case veryHigh = "VeryHigh"
    case exceptionallyHigh = "ExceptionallyHigh"

    private var rank: Int {
        switch self {
        case .lowToMedium: 0
        case .high: 1
        case .veryHigh: 2
        case .exceptionallyHigh: 3
        }
    }

    static func < (lhs: LoadFactor, rhs: LoadFactor) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - Remarks

nonisolated enum RemarkType: String, Codable, Hashable, Sendable {
    case hint = "Hint"
    case status = "Status"
}

nonisolated enum RemarkAssociation: String, Codable, Hashable, Sendable {
    case bike = "Bike"
    case accessibility = "Accessibility"
    case ticket = "Ticket"
    case power = "Power"
    case airConditioning = "AirConditioning"
    case wifi = "WiFi"
    case onlySecondClass = "OnlySecondClass"
    case unknown = "Unknown"
    case none = "None"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RemarkAssociation(rawValue: raw) ?? .unknown
    }
}

nonisolated struct Remark: Codable, Hashable, Sendable {
    var code: String
    var text: String
    var type: RemarkType
    var association: RemarkAssociation
    var summary: String?
    var tripId: String?

    enum CodingKeys: String, CodingKey {
        case code, text, type, association, summary
        case tripId = "trip_id"
    }
}

// MARK: - Legs

nonisolated struct Stop: Codable, Hashable, Sendable {
    var place: Place
    private var _departure: Nullable<ZonedTime>
    private var _plannedDeparture: Nullable<ZonedTime>
    private var _arrival: Nullable<ZonedTime>
    private var _plannedArrival: Nullable<ZonedTime>
    var arrivalPlatform: String?
    var plannedArrivalPlatform: String?
    var departurePlatform: String?
    var plannedDeparturePlatform: String?
    var cancelled: Bool
    var remarks: [Remark]

    enum CodingKeys: String, CodingKey {
        case place, cancelled, remarks
        case _departure = "departure"
        case _arrival = "arrival"
        case _plannedDeparture = "planned_departure"
        case _plannedArrival = "planned_arrival"
        case arrivalPlatform = "arrival_platform"
        case plannedArrivalPlatform = "planned_arrival_platform"
        case departurePlatform = "departure_platform"
        case plannedDeparturePlatform = "planned_departure_platform"
    }

    var departure: ZonedTime? {
        get { _departure.value }
        set { _departure = Nullable(newValue) }
    }

    var plannedDeparture: ZonedTime? {
        get { _plannedDeparture.value }
        set { _plannedDeparture = Nullable(newValue) }
    }

    var arrival: ZonedTime? {
        get { _arrival.value }
        set { _arrival = Nullable(newValue) }
    }

    var plannedArrival: ZonedTime? {
        get { _plannedArrival.value }
        set { _plannedArrival = Nullable(newValue) }
    }
}

nonisolated enum IntermediateLocation: Codable, Hashable, Sendable {
    /// A place where the train stops to let out passengers.
    case stop(Stop)
    /// A named railway track the train is passing over.
    case railway(Place)

    private enum Tag: String, CodingKey { case Stop, Railway }

    init(from decoder: Decoder) throws {
        let tagged = try decoder.container(keyedBy: Tag.self)
        if tagged.contains(.Stop) {
            self = .stop(try tagged.decode(Stop.self, forKey: .Stop))
        } else {
            self = .railway(try tagged.decode(Place.self, forKey: .Railway))
        }
    }

    func encode(to encoder: Encoder) throws {
        var tagged = encoder.container(keyedBy: Tag.self)
        switch self {
        case let .stop(stop): try tagged.encode(stop, forKey: .Stop)
        case let .railway(place): try tagged.encode(place, forKey: .Railway)
        }
    }
}

nonisolated struct Leg: Codable, Hashable, Sendable {
    var origin: Place
    var destination: Place
    private var _departure: Nullable<ZonedTime>
    private var _plannedDeparture: Nullable<ZonedTime>
    private var _arrival: Nullable<ZonedTime>
    private var _plannedArrival: Nullable<ZonedTime>
    var reachable: Bool
    var tripId: String?
    var line: Line?
    var direction: String?
    var arrivalPlatform: String?
    var plannedArrivalPlatform: String?
    var departurePlatform: String?
    var plannedDeparturePlatform: String?
    var frequency: Frequency?
    var cancelled: Bool
    var intermediateLocations: [IntermediateLocation]
    var loadFactor: LoadFactor?
    var remarks: [Remark]
    var walking: Bool
    var transfer: Bool
    var distance: UInt64?

    enum CodingKeys: String, CodingKey {
        case origin, destination, reachable, line, direction, frequency
        case _departure = "departure"
        case _arrival = "arrival"
        case cancelled, remarks, walking, transfer, distance
        case _plannedDeparture = "planned_departure"
        case _plannedArrival = "planned_arrival"
        case tripId = "trip_id"
        case arrivalPlatform = "arrival_platform"
        case plannedArrivalPlatform = "planned_arrival_platform"
        case departurePlatform = "departure_platform"
        case plannedDeparturePlatform = "planned_departure_platform"
        case intermediateLocations = "intermediate_locations"
        case loadFactor = "load_factor"
    }

    var departure: ZonedTime? {
        get { _departure.value }
        set { _departure = Nullable(newValue) }
    }

    var plannedDeparture: ZonedTime? {
        get { _plannedDeparture.value }
        set { _plannedDeparture = Nullable(newValue) }
    }

    var arrival: ZonedTime? {
        get { _arrival.value }
        set { _arrival = Nullable(newValue) }
    }

    var plannedArrival: ZonedTime? {
        get { _plannedArrival.value }
        set { _plannedArrival = Nullable(newValue) }
    }
}

nonisolated struct Price: Codable, Hashable, Sendable {
    var amount: Double
    var currency: String
}

nonisolated struct Journey: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var legs: [Leg]
    var price: Price?
}
