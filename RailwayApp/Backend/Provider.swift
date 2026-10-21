import Foundation

/// A transit network the user can search in.
struct Provider: Identifiable, Hashable, Sendable {
    /// Identifier understood by the backend and stored in the settings.
    var id: String
    var shortName: String
    var name: String?
    var region: String

    /// Name of the logo in the asset catalog.
    var iconName: String { "provider-\(id.lowercased())" }

    static let `default` = all.first { $0.id == "DB" }!

    static func with(id: String) -> Provider? {
        all.first { $0.id == id }
    }

    /// Kept in sync with Railway's `client.rs`.
    static let all: [Provider] = {
        let germany = String(localized: "Germany")
        let austria = String(localized: "Austria")
        let europe = String(localized: "Europe")
        let northAmerica = String(localized: "North America")
        return [
            Provider(id: "AVV", shortName: "AVV", name: "Aachener Verkehrsverbund", region: germany),
            Provider(id: "BART", shortName: "BART", name: "Bay Area Rapid Transit", region: northAmerica),
            Provider(id: "CFL", shortName: "CFL", name: "Société Nationale des Chemins de Fer Luxembourgeois", region: europe),
            Provider(id: "DB", shortName: "DB", name: "Deutsche Bahn", region: germany),
            Provider(id: "VGI", shortName: "VGI", name: "Verkehrsgemeinschaft Region Ingolstadt", region: germany),
            Provider(id: "Irish-Rail", shortName: "Irish Rail", name: "Iarnród Éireann", region: europe),
            Provider(id: "IVB", shortName: "IVB", name: "Innsbrucker Verkehrsbetriebe", region: austria),
            Provider(id: "KVB", shortName: "KVB", name: "Kölner Verkehrs-Betriebe", region: germany),
            Provider(id: "Mobiliteit-Lu", shortName: "Mobiliteit", name: "Luxembourg", region: europe),
            Provider(id: "NVV", shortName: "NVV", name: "Nordhessischer Verkehrsverbund", region: germany),
            Provider(id: "NahSH", shortName: "Nah.SH", name: String(localized: "Schleswig-Holstein"), region: germany),
            Provider(id: "ooevv", shortName: "OÖVV", name: "Oberösterreichischer Verkehrsverbund", region: austria),
            Provider(id: "OEBB", shortName: "ÖBB", name: "Österreichische Bundesbahnen", region: austria),
            Provider(id: "RMV", shortName: "RMV", name: "Rhein-Main-Verkehrsverbund", region: germany),
            Provider(id: "RSAG", shortName: "RSAG", name: "Rostocker Straßenbahn AG", region: germany),
            Provider(id: "Rejseplanen", shortName: "Rejseplanen", name: "Denmark", region: europe),
            Provider(id: "Resrobot", shortName: "Resrobot", name: "Sweden", region: europe),
            Provider(id: "SBahn-Muenchen", shortName: "S-Bahn München", name: germany, region: germany),
            Provider(id: "Verbundlinie", shortName: "Verbundlinie", name: "Steirischer Verkehrsverbund", region: austria),
            Provider(id: "SVV", shortName: "SVV", name: "Salzburger Verkehrsverbund", region: austria),
            Provider(id: "saarvv", shortName: "saarVV", name: "Saarfahrplan/VGS Saarland", region: germany),
            Provider(id: "Salzburg", shortName: "Salzburg", name: austria, region: austria),
            Provider(id: "VBB", shortName: "VBB", name: "Berlin & Brandenburg public transport", region: germany),
            Provider(id: "VBN", shortName: "VBN", name: "Verkehrsverbund Bremen/Niedersachsen", region: germany),
            Provider(id: "VKG", shortName: "VKG/VVK", name: "Kärntner Linien/Verkehrsverbund Kärnten", region: austria),
            Provider(id: "VMT", shortName: "VMT", name: "Verkehrsverbund Mittelthüringen", region: germany),
            Provider(id: "VOR", shortName: "VOR", name: "Verkehrsverbund Ost-Region", region: austria),
            Provider(id: "VOS", shortName: "VOS", name: "Verkehrsgemeinschaft Osnabrück", region: germany),
            Provider(id: "VSN", shortName: "VSN", name: "Verkehrsverbund Süd-Niedersachsen", region: germany),
            Provider(id: "VVT", shortName: "VVT", name: "Verkehrsverbund Tirol", region: austria),
            Provider(id: "VVV", shortName: "VVV", name: "Verkehrsverbund Vorarlberg", region: austria),
            Provider(id: "search-ch", shortName: "SBB", name: "Switzerland", region: europe),
            Provider(
                id: "transitous",
                shortName: String(localized: "Worldwide (beta)"),
                name: String(localized: "Using Transitous"),
                region: ""
            ),
        ]
        .filter { RailwayClient.availableProviders.contains(RailwayClient.normalize($0.id)) }
    }()

    /// Providers grouped by region; providers without a region come first.
    static var grouped: [(region: String, providers: [Provider])] {
        Dictionary(grouping: all, by: \.region)
            .map { (region: $0.key, providers: $0.value.sorted { $0.shortName.localizedStandardCompare($1.shortName) == .orderedAscending }) }
            .sorted { $0.region.localizedStandardCompare($1.region) == .orderedAscending }
    }
}
