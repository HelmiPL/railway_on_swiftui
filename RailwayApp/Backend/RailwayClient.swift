import Foundation

/// An error reported by the backend.
nonisolated struct BackendError: Error, Decodable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case request
        case provider
        case notImplemented = "not_implemented"
        case timeout
        case invalidRequest = "invalid_request"
    }

    var kind: Kind
    var message: String

    /// The short message shown to the user, mirroring Railway.
    var title: String {
        switch kind {
        case .request: String(localized: "Failed to fetch data. Are you connected to the internet?")
        case .provider: String(localized: "Received an error. Please share feedback.")
        default: String(localized: "An unknown issue occurred. Please share feedback.")
        }
    }

    /// Technical details, offered behind a "More Information" button.
    var details: String? {
        switch kind {
        case .request: nil
        case .provider: "Backend error: \(message)"
        case .timeout: "Timed Out"
        case .notImplemented: "Not implemented by this provider"
        case .invalidRequest: message
        }
    }
}

nonisolated enum TimeType: String, Codable, Sendable, CaseIterable {
    case departure
    case arrival
}

/// One page of journeys as returned by the backend.
nonisolated struct JourneysPage: Decodable, Sendable {
    var earlierRef: String?
    var laterRef: String?
    var journeys: [Journey]

    enum CodingKeys: String, CodingKey {
        case journeys
        case earlierRef = "earlier_ref"
        case laterRef = "later_ref"
    }
}

/// Everything except the places that is needed to query journeys.
nonisolated struct JourneyQueryOptions: Encodable, Sendable, Equatable {
    var firstClass = false
    var loyaltyCard = 0
    var bikeFriendly = false
    var directOnly = false
    var transferTimeMinutes = 0
    var products: [Mode]? = nil

    enum CodingKeys: String, CodingKey {
        case products
        case firstClass = "first_class"
        case loyaltyCard = "loyalty_card"
        case bikeFriendly = "bike_friendly"
        case directOnly = "direct_only"
        case transferTimeMinutes = "transfer_time_minutes"
    }
}

/// Async access to the Rust backend of a single provider.
nonisolated struct RailwayClient: Sendable {
    /// Provider identifier as understood by `railway-api`, e.g. `DB` or `search-ch`.
    var providerID: String

    /// All provider identifiers compiled into the backend.
    static let availableProviders: Set<String> = {
        let raw = rw_providers()
        defer { rw_string_free(raw) }
        let names = (try? JSONDecoder().decode([String].self, from: Data(String(cString: raw).utf8))) ?? []
        return Set(names.map(normalize))
    }()

    static func normalize(_ id: String) -> String {
        id.lowercased().replacing("-", with: "").replacing("_", with: "")
    }

    static var languageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    func locations(query: String, results: Int = 10) async throws -> [Place] {
        struct Request: Encodable { var query: String; var results: Int; var language: String }
        return try await call(rw_locations, Request(query: query, results: results, language: Self.languageCode))
    }

    func journeys(
        from: Place,
        to: Place,
        time: Date?,
        timeType: TimeType,
        earlierThan: String? = nil,
        laterThan: String? = nil,
        options: JourneyQueryOptions
    ) async throws -> JourneysPage {
        struct Request: Encodable {
            var from: Place
            var to: Place
            var time: Int64?
            var timeType: TimeType
            var earlierThan: String?
            var laterThan: String?
            var language: String
            var options: JourneyQueryOptions

            enum CodingKeys: String, CodingKey {
                case from, to, time, language
                case timeType = "time_type"
                case earlierThan = "earlier_than"
                case laterThan = "later_than"
            }

            func encode(to encoder: Encoder) throws {
                // The options are flattened into the request object.
                try options.encode(to: encoder)
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(from, forKey: .from)
                try c.encode(to, forKey: .to)
                try c.encodeIfPresent(time, forKey: .time)
                try c.encode(timeType, forKey: .timeType)
                try c.encodeIfPresent(earlierThan, forKey: .earlierThan)
                try c.encodeIfPresent(laterThan, forKey: .laterThan)
                try c.encode(language, forKey: .language)
            }
        }
        let request = Request(
            from: from,
            to: to,
            time: time.map { Int64($0.timeIntervalSince1970) },
            timeType: timeType,
            earlierThan: earlierThan,
            laterThan: laterThan,
            language: Self.languageCode,
            options: options
        )
        return try await call(rw_journeys, request)
    }

    func refresh(_ journey: Journey) async throws -> Journey {
        struct Request: Encodable { var journey: Journey; var language: String }
        return try await call(rw_refresh_journey, Request(journey: journey, language: Self.languageCode))
    }

    // MARK: Plumbing

    private typealias Function = (
        UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafeMutableRawPointer?, rw_callback
    ) -> Void

    private final class Box: @unchecked Sendable {
        let continuation: CheckedContinuation<Data, Never>
        init(_ continuation: CheckedContinuation<Data, Never>) { self.continuation = continuation }
    }

    private struct Envelope<T: Decodable>: Decodable {
        var ok: T?
        var error: BackendError?
    }

    private func call<Request: Encodable, Response: Decodable>(
        _ function: Function,
        _ request: Request
    ) async throws -> Response {
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let data = await withCheckedContinuation { continuation in
            let context = Unmanaged.passRetained(Box(continuation)).toOpaque()
            function(providerID, json, context) { context, result in
                let box = Unmanaged<Box>.fromOpaque(context!).takeRetainedValue()
                box.continuation.resume(returning: Data(String(cString: result).utf8))
            }
        }
        let envelope = try JSONDecoder().decode(Envelope<Response>.self, from: data)
        if let error = envelope.error { throw error }
        guard let ok = envelope.ok else {
            throw BackendError(kind: .provider, message: "Empty response")
        }
        return ok
    }
}
