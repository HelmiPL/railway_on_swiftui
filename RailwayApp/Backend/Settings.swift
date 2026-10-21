import Foundation

/// User defaults keys, named after Railway's GSettings schema.
enum SettingsKey {
    static let provider = "search-provider"
    static let searchFrom = "search-from"
    static let searchTo = "search-to"

    static let loyaltyCard = "bahncard"
    static let firstClass = "first-class"
    static let bikeAccessible = "bike-accessible"
    static let transferTime = "transfer-time"
    static let directOnly = "direct-only"

    static let deleteOld = "delete-old"
    static let deletionTime = "deletion-time"
    static let bookmarkPurgeSuggested = "bookmark-purge-suggested"

    static let animateBackground = "animate-trip-background"
    static let alwaysShowTabBar = "always-show-tab-bar"
    /// iPad: a close button where the window controls are, which iPadOS hides in full screen.
    static let fullScreenCloseButton = "full-screen-close-button"

    static func include(_ mode: TransportMode) -> String { "include-\(mode.rawValue)" }
}

/// The modes of transport that can be toggled in the search options.
enum TransportMode: String, CaseIterable, Identifiable {
    case nationalExpress = "national-express"
    case regional
    case suburban
    case bus
    case ferry
    case subway
    case tram
    case cablecar
    case taxi

    var id: Self { self }

    var title: String {
        switch self {
        case .nationalExpress: String(localized: "Mainline Train")
        case .regional: String(localized: "Regional Train")
        case .suburban: String(localized: "S-Bahn Train")
        case .bus: String(localized: "Bus")
        case .ferry: String(localized: "Ferry")
        case .subway: String(localized: "Subway")
        case .tram: String(localized: "Tram")
        case .cablecar: String(localized: "Cablecar")
        case .taxi: String(localized: "Taxi")
        }
    }

    var systemImage: String {
        switch self {
        case .nationalExpress: "train.side.front.car"
        case .regional: "train.side.rear.car"
        case .suburban: "lightrail"
        case .bus: "bus"
        case .ferry: "ferry"
        case .subway: "tram.fill.tunnel"
        case .tram: "tram"
        case .cablecar: "cablecar"
        case .taxi: "car"
        }
    }

    var backendMode: Mode {
        switch self {
        case .nationalExpress: .highSpeedTrain
        case .regional: .regionalTrain
        case .suburban: .suburbanTrain
        case .bus: .bus
        case .ferry: .ferry
        case .subway: .subway
        case .tram: .tram
        case .cablecar: .cablecar
        case .taxi: .onDemand
        }
    }
}

/// Discount cards, with the ids used by the backend.
enum LoyaltyCard: Int, CaseIterable, Identifiable {
    case none = 0
    case bahnCard25First = 1
    case bahnCard25Second = 2
    case bahnCard50First = 3
    case bahnCard50Second = 4
    case vorteilscard = 9
    case halbtaxaboRailplus = 10
    case halbtaxabo = 11
    case voordeelurenaboRailplus = 12
    case voordeelurenabo = 13
    case shCard = 14
    case generalabonnement = 15

    var id: Self { self }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .bahnCard25First: String(localized: "BahnCard 25, 1st class")
        case .bahnCard25Second: String(localized: "BahnCard 25, 2nd class")
        case .bahnCard50First: String(localized: "BahnCard 50, 1st class")
        case .bahnCard50Second: String(localized: "BahnCard 50, 2nd class")
        case .vorteilscard: String(localized: "A – VORTEILScard (with RAILPLUS)")
        case .halbtaxaboRailplus: String(localized: "CH – HalbtaxAbo (with RAILPLUS)")
        case .halbtaxabo: String(localized: "CH – HalbtaxAbo (without RAILPLUS)")
        case .voordeelurenaboRailplus: String(localized: "NL – Voordeelurenabo (with RAILPLUS)")
        case .voordeelurenabo: String(localized: "NL – Voordeelurenabo (without RAILPLUS)")
        case .shCard: String(localized: "SH-Card")
        case .generalabonnement: String(localized: "CH – General-Abonnement")
        }
    }
}

extension UserDefaults {
    static func registerRailwayDefaults() {
        var defaults: [String: Any] = [
            SettingsKey.provider: Provider.default.id,
            SettingsKey.deletionTime: 2,
            SettingsKey.animateBackground: true,
            SettingsKey.fullScreenCloseButton: true,
        ]
        for mode in TransportMode.allCases {
            defaults[SettingsKey.include(mode)] = true
        }
        standard.register(defaults: defaults)
    }

    /// The search options as currently configured by the user.
    var journeyQueryOptions: JourneyQueryOptions {
        let modes = TransportMode.allCases.filter { bool(forKey: SettingsKey.include($0)) }
        return JourneyQueryOptions(
            firstClass: bool(forKey: SettingsKey.firstClass),
            loyaltyCard: integer(forKey: SettingsKey.loyaltyCard),
            bikeFriendly: bool(forKey: SettingsKey.bikeAccessible),
            directOnly: bool(forKey: SettingsKey.directOnly),
            transferTimeMinutes: integer(forKey: SettingsKey.transferTime),
            products: modes.count == TransportMode.allCases.count ? nil : modes.map(\.backendMode)
        )
    }

    /// The summary shown below "More Options", e.g. `2nd class · BahnCard 25 · Bike Accessible`.
    var searchOptionsSummary: String {
        let included = TransportMode.allCases.map { bool(forKey: SettingsKey.include($0)) }
        let regionalOnly = !included[0] && included.dropFirst().allSatisfy { $0 }
        let card = LoyaltyCard(rawValue: integer(forKey: SettingsKey.loyaltyCard)) ?? .none
        return [
            bool(forKey: SettingsKey.firstClass) ? String(localized: "1st class") : String(localized: "2nd class"),
            card == .none ? nil : card.title,
            included.allSatisfy { $0 } ? nil
                : regionalOnly ? String(localized: "Regional Only") : String(localized: "Selected Modes of Transport"),
            bool(forKey: SettingsKey.bikeAccessible) ? String(localized: "Bike Accessible") : nil,
            bool(forKey: SettingsKey.directOnly) ? String(localized: "Direct Connection") : nil,
        ]
        .compactMap(\.self)
        .joined(separator: "\u{00A0}· ")
    }
}
