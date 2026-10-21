import Foundation
import Observation

private func storeURL(_ name: String) -> URL {
    let directory = URL.applicationSupportDirectory.appending(path: "Railway", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: name)
}

/// Bookmarked journeys and which of them are watched, ported from Railway's `journey_store.rs`.
@Observable
final class JourneyStore {
    /// The on-disk format; compatible with Railway's `journeys_store.json` plus the provider of each journey.
    private struct StorageData: Codable {
        var journeys: [Journey] = []
        var watched: [String: NotifyStatus] = [:]
        var providers: [String: String]? = [:]
    }

    private let url = storeURL("journeys_store.json")
    private let registry: JourneyRegistry
    private let tracker: LiveTracker

    private(set) var journeys: [JourneyModel] = []
    private(set) var watched: Set<String> = []

    /// Set when old bookmarks could be purged but the user was not asked about it yet.
    private(set) var hasDeletableJourneys = false

    init(registry: JourneyRegistry, tracker: LiveTracker) {
        self.registry = registry
        self.tracker = tracker
    }

    func contains(_ journey: JourneyModel) -> Bool {
        journeys.contains { $0.id == journey.id }
    }

    func isWatched(_ journey: JourneyModel) -> Bool {
        watched.contains(journey.id)
    }

    func toggle(_ journey: JourneyModel) {
        if contains(journey) {
            remove(journey)
        } else {
            journeys.append(journey)
            sort()
        }
        flush()
    }

    func remove(_ journey: JourneyModel) {
        journeys.removeAll { $0.id == journey.id }
        if watched.remove(journey.id) != nil {
            tracker.unregisterBackground(journey)
        }
        flush()
    }

    func toggleWatch(_ journey: JourneyModel) {
        if watched.remove(journey.id) != nil {
            tracker.unregisterBackground(journey)
        } else {
            Notifier.requestAuthorization()
            watched.insert(journey.id)
            tracker.registerBackground(journey)
        }
        flush()
    }

    func load(defaultProvider: String) {
        let defaults = UserDefaults.standard
        let data = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(StorageData.self, from: $0) }
            ?? StorageData()

        let deletionTime = TimeInterval(defaults.integer(forKey: SettingsKey.deletionTime) * 60 * 60)
        var deletable = false
        journeys = []
        watched = []
        for journey in data.journeys {
            let couldBeDeleted = journey.arrival.map { $0.date + deletionTime < .now } ?? true
            if couldBeDeleted {
                if defaults.bool(forKey: SettingsKey.deleteOld) {
                    defaults.set(true, forKey: SettingsKey.bookmarkPurgeSuggested)
                    continue
                } else if !defaults.bool(forKey: SettingsKey.bookmarkPurgeSuggested) {
                    deletable = true
                }
            }
            let model = registry.model(for: journey, providerID: data.providers?[journey.id] ?? defaultProvider)
            journeys.append(model)
            if let status = data.watched[journey.id] {
                model.notifyStatus = status
                watched.insert(journey.id)
                tracker.registerBackground(model)
            }
        }
        sort()
        hasDeletableJourneys = deletable
        flush()
    }

    func flush() {
        var data = StorageData()
        data.journeys = journeys.map(\.journey)
        data.providers = Dictionary(uniqueKeysWithValues: journeys.map { ($0.id, $0.providerID) })
        for journey in journeys where watched.contains(journey.id) {
            data.watched[journey.id] = journey.notifyStatus
        }
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: url, options: .atomic)
        }
    }

    private func sort() {
        journeys.sort { ($0.journey.departure?.date ?? .distantPast) < ($1.journey.departure?.date ?? .distantPast) }
    }
}

/// A bookmarked search between two places, identified by their names.
struct SavedSearch: Codable, Hashable, Identifiable {
    var origin: String
    var destination: String

    var id: String { "\(origin)\u{1F}\(destination)" }
}

/// Bookmarked searches, ported from Railway's `search_store.rs`.
@Observable
final class SearchStore {
    private let url = storeURL("search_store.json")
    private(set) var searches: [SavedSearch] = []

    init() {
        searches = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([SavedSearch].self, from: $0) } ?? []
    }

    func contains(origin: String, destination: String) -> Bool {
        searches.contains(SavedSearch(origin: origin, destination: destination))
    }

    func toggle(origin: String, destination: String) {
        let search = SavedSearch(origin: origin, destination: destination)
        if let index = searches.firstIndex(of: search) {
            searches.remove(at: index)
        } else {
            searches.append(search)
        }
        flush()
    }

    func remove(_ search: SavedSearch) {
        searches.removeAll { $0 == search }
        flush()
    }

    private func flush() {
        if let encoded = try? JSONEncoder().encode(searches) {
            try? encoded.write(to: url, options: .atomic)
        }
    }
}

/// Runs the background tasks of watched journeys, ported from Railway's `timer.rs`.
@MainActor
final class LiveTracker {
    private var background: [String: Task<Void, Never>] = [:]
    private var minutely: [String: Task<Void, Never>] = [:]

    /// Called after background tasks ran, e.g. to persist the notification status.
    var onTasksRan: (() -> Void)?

    /// Run the background tasks at a pace depending on how soon the next event is.
    func registerBackground(_ journey: JourneyModel) {
        background[journey.id]?.cancel()
        background[journey.id] = Task { [weak self] in
            while let sleep = journey.nextBackgroundTasksIn {
                try? await Task.sleep(for: sleep)
                guard !Task.isCancelled else { return }
                // Don't run them twice if the journey is already updated every minute.
                if self?.minutely[journey.id] == nil {
                    await journey.runBackgroundTasks()
                    self?.onTasksRan?()
                }
            }
            self?.background[journey.id] = nil
        }
    }

    func unregisterBackground(_ journey: JourneyModel) {
        background.removeValue(forKey: journey.id)?.cancel()
    }

    /// Run the background tasks every minute, while the live banner is visible.
    func registerMinutely(_ journey: JourneyModel) {
        guard minutely[journey.id] == nil else { return }
        minutely[journey.id] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await journey.runBackgroundTasks()
                self?.onTasksRan?()
            }
        }
    }

    func unregisterMinutely(_ journey: JourneyModel) {
        minutely.removeValue(forKey: journey.id)?.cancel()
    }
}
