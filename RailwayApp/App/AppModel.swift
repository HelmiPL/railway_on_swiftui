import Foundation
import Observation
import SwiftUI

/// The connections found for a search, which can be extended with earlier and later ones.
@Observable
final class JourneysResult {
    let source: Place
    let destination: Place
    let timeType: TimeType
    let requestedTime: Date
    let providerID: String
    private(set) var journeys: [JourneyModel]
    private(set) var earlierRef: String?
    private(set) var laterRef: String?

    init(source: Place, destination: Place, timeType: TimeType, requestedTime: Date, providerID: String,
         page: JourneysPage, registry: JourneyRegistry) {
        self.source = source
        self.destination = destination
        self.timeType = timeType
        self.requestedTime = requestedTime
        self.providerID = providerID
        journeys = page.journeys.map { registry.model(for: $0, providerID: providerID) }
        earlierRef = page.earlierRef
        laterRef = page.laterRef
    }

    /// Prepend earlier journeys, skipping duplicates.
    func mergePrepend(_ page: JourneysPage, registry: JourneyRegistry) {
        let ids = Set(journeys.map(\.id))
        let new = page.journeys.filter { !ids.contains($0.id) }.map { registry.model(for: $0, providerID: providerID) }
        journeys.insert(contentsOf: new, at: 0)
        earlierRef = page.earlierRef
    }

    /// Append later journeys, skipping duplicates.
    func mergeAppend(_ page: JourneysPage, registry: JourneyRegistry) {
        let ids = Set(journeys.map(\.id))
        journeys += page.journeys.filter { !ids.contains($0.id) }.map { registry.model(for: $0, providerID: providerID) }
        laterRef = page.laterRef
    }

    /// Journeys grouped by the day they depart on.
    var days: [(day: Date, journeys: [JourneyModel])] {
        let calendar = Calendar.current
        var days: [(day: Date, journeys: [JourneyModel])] = []
        for journey in journeys {
            let day = calendar.startOfDay(for: journey.journey.departure?.date ?? requestedTime)
            if days.last?.day == day {
                days[days.count - 1].journeys.append(journey)
            } else {
                days.append((day, [journey]))
            }
        }
        return days
    }
}

/// A transient message shown at the bottom of the window.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var actionTitle: String?
    /// Stays until dismissed if `false`.
    var autoDismiss = true
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

/// Details offered by an error toast.
struct ErrorDetails: Identifiable {
    let id = UUID()
    var message: String
}

/// State shared by all windows: bookmarks, the journey cache and live tracking.
@MainActor
final class RailwayServices {
    static let shared = RailwayServices()

    let registry = JourneyRegistry()
    let tracker = LiveTracker()
    let journeyStore: JourneyStore
    let searchStore = SearchStore()
    /// Whether old bookmarks can be purged; suggested once, in the first window.
    private var purgeSuggestionPending: Bool

    private init() {
        UserDefaults.registerRailwayDefaults()
        journeyStore = JourneyStore(registry: registry, tracker: tracker)
        tracker.onTasksRan = { [journeyStore] in journeyStore.flush() }
        let provider = Provider.with(id: UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "") ?? .default
        journeyStore.load(defaultProvider: provider.id)
        purgeSuggestionPending = journeyStore.hasDeletableJourneys
    }

    func consumePurgeSuggestion() -> Bool {
        defer { purgeSuggestionPending = false }
        return purgeSuggestionPending
    }
}

/// The state of one window: its search, results, selection and messages.
@Observable
final class AppModel {
    private let defaults = UserDefaults.standard
    let services: RailwayServices

    var registry: JourneyRegistry { services.registry }
    var tracker: LiveTracker { services.tracker }
    var journeyStore: JourneyStore { services.journeyStore }
    var searchStore: SearchStore { services.searchStore }

    private(set) var provider: Provider
    var client: RailwayClient { RailwayClient(providerID: provider.id) }

    // Search
    let from: StationField
    let to: StationField
    var timeType = TimeType.departure
    /// Search from the current time instead of `date`.
    var useNow = true
    var date = Date.now
    private(set) var searching = false
    /// Search as soon as both places are resolved (used by bookmarked searches).
    private var searchWhenReady = false
    /// Incremented to move keyboard focus to the "From" field.
    private(set) var focusFromRequest = 0

    // Layout
    var columnVisibility = NavigationSplitViewVisibility.all
    /// Too narrow for three columns: trips open in their own windows.
    var isCompact = false
    /// Whether this window shows the search (trip windows do not).
    let hasSearch: Bool
    /// Whether the window's tab bar is showing (native on the Mac, `WindowTabBar` on iPad).
    var tabBarVisible = false
    /// Whether the pointer is over the toolbar above the trip details.
    var toolbarHovered = false
    /// Where the trip details column starts, in window coordinates.
    var detailMinX: CGFloat = 0

    /// Whether search, connections and trip details are columns of one window, as on the Mac.
    /// iOS/iPadOS uses tabs instead while the window is narrow (on iPhone, and in small iPad windows).
    var usesSplitView = true

    #if os(iOS)
    enum Tab { case search, bookmarks, settings }

    var selectedTab = Tab.search
    /// Whether the selected journey is shown in a sheet.
    var isTripPresented = false
    /// Whether the settings are shown in a sheet (iPad; iPhone has a tab for them).
    var isSettingsPresented = false
    /// Whether the full-screen close button is showing in the window's top-left corner.
    var showsCloseButton = false
    /// With the sidebar hidden, the leftmost column's toolbar starts in that corner; iPadOS only
    /// leaves room there for its own window controls, so the sidebar button is replaced by one
    /// placed after the close button.
    var replacesSidebarToggle: Bool { showsCloseButton && !isSidebarVisible }
    /// Where the toolbar ends, in window coordinates: the iPad's tab bar goes right below it.
    var tabBarTop: CGFloat = 0
    /// Where the connections column starts: the tab bar spans it and the trip column, not the
    /// sidebar.
    var tabBarLeading: CGFloat = 0
    /// Where the trip column starts, to hide the divider before it within the toolbar.
    var tabBarDividerX: CGFloat = 0
    /// The line the toolbar's buttons are centred on, in global coordinates: for the tab bar's
    /// separator and the full-screen close button.
    var toolbarCentreY: CGFloat = 0
    #endif

    /// Shows a journey's details: in the detail column if there is one, otherwise in a sheet on
    /// iOS/iPadOS (the Mac opens a window instead, see the callers).
    func open(_ journey: JourneyModel) {
        selectedJourney = journey
        #if os(iOS)
        if !usesSplitView || isCompact {
            isTripPresented = true
        }
        #endif
    }

    /// What to draw behind the toolbar above a column.
    /// - `raised`: an opaque bar set apart from the content: lighter in dark mode, light grey in
    ///   light mode (used by the Settings window).
    enum ToolbarBand { case none, hover, tabs, raised }

    /// With tabs, the connections and trip columns share one opaque toolbar band.
    var contentToolbarBand: ToolbarBand { tabBarVisible ? .tabs : .none }

    /// Above the trip details the toolbar band only shows on hover, unless tabs are visible.
    var detailToolbarBand: ToolbarBand {
        if tabBarVisible { return .tabs }
        #if DEBUG
        if ProcessInfo.processInfo.environment["RAILWAY_TOOLBAR_HOVER"] != nil { return .hover }
        #endif
        return toolbarHovered ? .hover : .none
    }

    // Results
    private(set) var result: JourneysResult?
    private(set) var loadingEarlier = false
    private(set) var loadingLater = false
    var selectedJourney: JourneyModel?

    // Feedback
    var toast: Toast?
    var errorDetails: ErrorDetails?

    /// - Parameter hasSearch: `false` for windows showing a single trip; they don't restore the search.
    init(services: RailwayServices = .shared, hasSearch: Bool = true) {
        self.services = services
        self.hasSearch = hasSearch
        let provider = Provider.with(id: UserDefaults.standard.string(forKey: SettingsKey.provider) ?? "") ?? .default
        self.provider = provider
        let client = RailwayClient(providerID: provider.id)
        from = StationField(client: client)
        to = StationField(client: client)
        guard hasSearch else { return }

        from.setInput(defaults.string(forKey: SettingsKey.searchFrom) ?? "")
        to.setInput(defaults.string(forKey: SettingsKey.searchTo) ?? "")
        if services.consumePurgeSuggestion() {
            suggestPurgingBookmarks()
        }
    }

    // MARK: Layout

    var isSidebarVisible: Bool { columnVisibility == .all }

    func toggleSidebar() {
        withAnimation {
            columnVisibility = isSidebarVisible ? (isCompact ? .detailOnly : .doubleColumn) : .all
        }
    }

    func focusFrom() {
        if !isSidebarVisible { toggleSidebar() }
        focusFromRequest += 1
    }

    // MARK: Provider

    func selectProvider(_ provider: Provider) {
        guard provider != self.provider else { return }
        self.provider = provider
        defaults.set(provider.id, forKey: SettingsKey.provider)
        from.reset(client: client)
        to.reset(client: client)
    }

    // MARK: Search

    var canSearch: Bool { from.isSet && to.isSet && !searching }

    /// Why searching is not possible right now.
    var searchUnavailableReason: String? {
        switch (from.isSet, to.isSet, searching) {
        case (false, false, _): String(localized: "Start and destination are missing")
        case (false, true, _): String(localized: "Start is missing")
        case (true, false, _): String(localized: "Destination is missing")
        case (true, true, true): String(localized: "Search ongoing")
        case (true, true, false): nil
        }
    }

    func swapPlaces() {
        from.swap(with: to)
    }

    /// Persist the text of the search fields, so they are restored on the next launch.
    func saveSearchInputs() {
        defaults.set(from.text, forKey: SettingsKey.searchFrom)
        defaults.set(to.text, forKey: SettingsKey.searchTo)
    }

    func search() {
        guard canSearch, let source = from.place, let destination = to.place else { return }
        saveSearchInputs()
        let timeType = timeType
        let providerID = provider.id
        // Set right away, so the search can't be started twice.
        searching = true
        Task {
            await search(from: source, to: destination, timeType: timeType, providerID: providerID)
        }
    }

    /// Searches the shown connections again, e.g. when pulling to refresh.
    func reloadResults() async {
        guard let result, !searching else { return }
        await search(from: result.source, to: result.destination, timeType: result.timeType, providerID: result.providerID)
    }

    private func search(from source: Place, to destination: Place, timeType: TimeType, providerID: String) async {
        let time = useNow ? Date.now : date
        searching = true
        defer { searching = false }
        do {
            let page = try await RailwayClient(providerID: providerID).journeys(
                from: source, to: destination, time: time, timeType: timeType,
                options: defaults.journeyQueryOptions
            )
            result = JourneysResult(
                source: source, destination: destination, timeType: timeType, requestedTime: time,
                providerID: providerID, page: page, registry: registry
            )
        } catch {
            show(error)
        }
    }

    /// Fill in a bookmarked search and run it once both places are resolved.
    func run(_ search: SavedSearch) {
        from.setInput(search.origin)
        to.setInput(search.destination)
        searchWhenReady = true
        Task {
            // Resolving takes at least the debounce time; give up after the request timeout.
            for _ in 0..<35 where searchWhenReady {
                if canSearch {
                    searchWhenReady = false
                    self.search()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
            searchWhenReady = false
        }
    }

    func loadEarlier() {
        guard let result, !loadingEarlier else { return }
        loadingEarlier = true
        Task {
            defer { loadingEarlier = false }
            do {
                let page = try await RailwayClient(providerID: result.providerID).journeys(
                    from: result.source, to: result.destination, time: nil, timeType: result.timeType,
                    earlierThan: result.earlierRef, options: defaults.journeyQueryOptions
                )
                result.mergePrepend(page, registry: registry)
            } catch {
                show(error)
            }
        }
    }

    func loadLater() {
        guard let result, !loadingLater else { return }
        loadingLater = true
        Task {
            defer { loadingLater = false }
            do {
                let page = try await RailwayClient(providerID: result.providerID).journeys(
                    from: result.source, to: result.destination, time: nil, timeType: result.timeType,
                    laterThan: result.laterRef, options: defaults.journeyQueryOptions
                )
                result.mergeAppend(page, registry: registry)
            } catch {
                show(error)
            }
        }
    }

    // MARK: Bookmarks

    var isResultBookmarked: Bool {
        guard let result else { return false }
        return searchStore.contains(origin: result.source.name, destination: result.destination.name)
    }

    func toggleResultBookmark() {
        guard let result else { return }
        searchStore.toggle(origin: result.source.name, destination: result.destination.name)
    }

    func toggleBookmark(_ journey: JourneyModel) {
        journeyStore.toggle(journey)
    }

    func toggleWatch(_ journey: JourneyModel) {
        journeyStore.toggleWatch(journey)
    }

    func refresh(_ journey: JourneyModel) {
        Task { await reload(journey) }
    }

    /// Refreshes a journey and waits for it, e.g. when pulling to refresh.
    func reload(_ journey: JourneyModel) async {
        do {
            try await journey.refresh()
            if journeyStore.contains(journey) { journeyStore.flush() }
        } catch {
            show(error)
        }
    }

    private func suggestPurgingBookmarks() {
        toast = Toast(
            title: String(localized: "A bookmarked trip ended recently."),
            actionTitle: String(localized: "Always Delete"),
            autoDismiss: false,
            action: { [defaults] in defaults.set(true, forKey: SettingsKey.deleteOld) },
            onDismiss: { [defaults] in defaults.set(true, forKey: SettingsKey.bookmarkPurgeSuggested) }
        )
    }

    // MARK: Errors

    func show(_ error: Error) {
        let error = error as? BackendError ?? BackendError(kind: .provider, message: error.localizedDescription)
        toast = Toast(
            title: error.title,
            actionTitle: error.details == nil ? nil : String(localized: "More Information"),
            action: error.details.map { details in { [weak self] in self?.errorDetails = ErrorDetails(message: details) } }
        )
    }
}
