import Foundation
import Observation
import UserNotifications

/// What is currently happening on a journey, ported from Railway's `journey.rs`.
enum JourneyEvent: Equatable {
    case beforeJourney(Leg)
    case inLeg(Leg, next: Leg?)
    case transitionTo(Leg)
    case afterJourney

    var currentLeg: Leg? {
        if case let .inLeg(leg, _) = self { leg } else { nil }
    }

    var nextLeg: Leg? {
        switch self {
        case let .beforeJourney(leg), let .transitionTo(leg): leg
        case let .inLeg(_, next): next
        case .afterJourney: nil
        }
    }

    var timeOfNextAction: Date? {
        switch self {
        case let .beforeJourney(leg), let .transitionTo(leg): leg.departure?.date
        case let .inLeg(leg, _): leg.arrival?.date
        case .afterJourney: nil
        }
    }

    /// The text of the live banner.
    func description(at now: Date) -> String {
        let remaining = timeOfNextAction.map { Format.durationTabular(.seconds(max($0.timeIntervalSince(now), 0))) }
        let nextName = nextLeg?.displayName
        let nextPlatform = nextLeg?.departurePlatform
        let nextOrigin = nextLeg?.origin.name

        switch self {
        case .beforeJourney:
            guard let remaining, let nextOrigin else { return "" }
            if let nextPlatform {
                return String(localized: "Start at \(nextOrigin) in \(remaining) on platform \(nextPlatform)")
            }
            return String(localized: "Start at \(nextOrigin) in \(remaining)")
        case let .inLeg(leg, _):
            guard let remaining else { return "" }
            return String(localized: "Arriving at \(leg.destination.name) in \(remaining)")
        case .transitionTo:
            guard let remaining, let nextName else { return "" }
            if let nextPlatform {
                return String(localized: "Change to \(nextName) on platform \(nextPlatform), remaining: \(remaining)")
            }
            return String(localized: "Change to \(nextName), remaining: \(remaining)")
        case .afterJourney:
            return String(localized: "The trip’s destination has been reached")
        }
    }
}

/// Something about a journey the user should be warned about.
enum JourneyAlert: Equatable {
    case departureDelayed(Leg)
    case arrivalDelayed(Leg)
    case departurePlatformChange(Leg)
    case legUnreachable(Leg)
    case legCancelled(Leg)
}

/// Which notifications were already sent for a watched journey, so they are not repeated.
struct NotifyStatus: Codable, Equatable {
    var beginningOfJourney = false
    var inLegSoonTransition: Set<String> = []
    var unreachable: Set<String> = []
    var cancelled: Set<String> = []
    var departureDelays: [String: Int] = [:]
    var arrivalDelays: [String: Int] = [:]
    var departurePlatformChanges: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case unreachable, cancelled
        case beginningOfJourney = "beginning_of_journey"
        case inLegSoonTransition = "in_leg_soon_transition"
        case departureDelays = "departure_delays"
        case arrivalDelays = "arrival_delays"
        case departurePlatformChanges = "departure_platform_changes"
    }
}

/// A journey as shown in the app: the backend data plus refresh and live tracking state.
///
/// Instances are shared through `JourneyRegistry`, so a bookmarked journey and the same journey
/// in the search results are the same object.
@Observable
final class JourneyModel: Identifiable {
    let id: String
    /// The provider the journey was found with; needed to refresh it.
    let providerID: String
    private(set) var journey: Journey
    private(set) var refreshInProgress = false
    private(set) var lastRefreshed = Date.now
    var notifyStatus = NotifyStatus()

    init(journey: Journey, providerID: String) {
        id = journey.id
        self.journey = journey
        self.providerID = providerID
    }

    func update(_ journey: Journey) {
        self.journey = journey
    }

    func refresh() async throws {
        refreshInProgress = true
        defer { refreshInProgress = false }
        let refreshed = try await RailwayClient(providerID: providerID).refresh(journey)
        journey = refreshed
        lastRefreshed = .now
    }

    // MARK: Live tracking

    func event(at time: Date = .now) -> JourneyEvent {
        let legs = journey.legs
        for (index, leg) in legs.enumerated() {
            if let departure = leg.departure, time < departure.date {
                return index == 0 ? .beforeJourney(leg) : .transitionTo(leg)
            } else if let arrival = leg.arrival, time < arrival.date, !leg.walking {
                return .inLeg(leg, next: legs[(index + 1)...].first { !$0.walking })
            }
        }
        return .afterJourney
    }

    func alerts(at time: Date = .now) -> [JourneyAlert] {
        var alerts: [JourneyAlert] = []
        for leg in journey.legs where !leg.walking {
            // Only alert about future legs.
            if let departure = leg.departure, time < departure.date {
                if leg.cancelled {
                    alerts.append(.legCancelled(leg))
                    continue
                }
                if !leg.reachable {
                    alerts.append(.legUnreachable(leg))
                    continue
                }
                if leg.departure != leg.plannedDeparture { alerts.append(.departureDelayed(leg)) }
                if leg.departurePlatform != leg.plannedDeparturePlatform { alerts.append(.departurePlatformChange(leg)) }
                if leg.arrival != leg.plannedArrival { alerts.append(.arrivalDelayed(leg)) }
            }
            if let arrival = leg.arrival, time < arrival.date, leg.arrival != leg.plannedArrival {
                alerts.append(.arrivalDelayed(leg))
            }
        }
        return alerts
    }

    /// Time until the next scheduled event, if it is in the future.
    private func durationToNextEvent(_ event: JourneyEvent) -> TimeInterval? {
        event.timeOfNextAction.map { $0.timeIntervalSinceNow }.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// Refresh more often the closer the next event is.
    private var shouldRefresh: Bool {
        guard let next = durationToNextEvent(event()) else { return false }
        let sinceRefresh = Date.now.timeIntervalSince(lastRefreshed)
        let minute: TimeInterval = 60
        let hour = 60 * minute
        return (next < 24 * hour && sinceRefresh > hour)
            || (next < hour && sinceRefresh > 15 * minute)
            || (next < 15 * minute && sinceRefresh > 5 * minute)
            || (next < 5 * minute && sinceRefresh > minute)
    }

    /// When the background tasks should run next, or `nil` if the journey is over.
    var nextBackgroundTasksIn: Duration? {
        let event = event()
        guard let next = durationToNextEvent(event) else { return nil }
        let minute: TimeInterval = 60
        let isInLeg = if case .inLeg = event { true } else { false }
        return switch next {
        case ..<(10 * minute): .seconds(60)
        case ..<(30 * minute): .seconds(5 * 60)
        case _ where next < 2 * 60 * minute || isInLeg: .seconds(15 * 60)
        case ..<(2 * 24 * 60 * minute): .seconds(60 * 60)
        default: .seconds(24 * 60 * 60)
        }
    }

    /// Refresh if needed and send notifications about what changed.
    func runBackgroundTasks() async {
        if shouldRefresh {
            // Errors are ignored; the next run tries again.
            try? await refresh()
        }
        potentiallyNotify()
    }

    private func potentiallyNotify() {
        let event = event()
        let toNext = durationToNextEvent(event)

        switch event {
        case let .beforeJourney(leg) where (toNext ?? .infinity) < 60 * 60 && !notifyStatus.beginningOfJourney:
            notifyStatus.beginningOfJourney = true
            let time = Format.time(leg.departure) ?? ""
            let body = if let platform = leg.departurePlatform {
                String(localized: "Start at \(leg.origin.name) on platform \(platform) at \(time)")
            } else {
                String(localized: "Start at \(leg.origin.name) at \(time)")
            }
            Notifier.send(
                id: "railway-journey-current-event-\(id)",
                title: String(localized: "Trip to \(journey.destinationName) will begin shortly"),
                body: body
            )
        case let .inLeg(leg, next) where (toNext ?? .infinity) < 5 * 60
            && !notifyStatus.inLegSoonTransition.contains(leg.stableID):
            notifyStatus.inLegSoonTransition.insert(leg.stableID)
            if let next {
                let transfer = next.departure.flatMap { departure in leg.arrival.map { departure - $0 } }
                    .map(Format.durationInline)
                let body: String? = switch (next.departurePlatform, transfer) {
                case let (platform?, time?): String(localized: "\(time) transfer time to get to platform \(platform)")
                case let (nil, time?): String(localized: "\(time) transfer time")
                case let (platform?, nil): String(localized: "Upcoming departure on platform \(platform)")
                case (nil, nil): nil
                }
                Notifier.send(
                    id: "railway-journey-current-event-\(id)",
                    title: String(localized: "Upcoming transfer at \(leg.destination.name) soon"),
                    body: body
                )
            } else {
                Notifier.send(
                    id: "railway-journey-current-event-\(id)",
                    title: String(localized: "Arriving at \(leg.destination.name) soon"),
                    body: nil
                )
            }
        default:
            break
        }

        for alert in alerts() {
            switch alert {
            case let .departureDelayed(leg):
                guard let real = leg.departure, let planned = leg.plannedDeparture else { continue }
                let delay = (real - planned).minutes
                if delay - notifyStatus.departureDelays[leg.stableID, default: 0] >= 5 {
                    notifyStatus.departureDelays[leg.stableID] = delay
                    Notifier.send(
                        id: "railway-leg-departure-delayed-\(leg.stableID)",
                        title: String(localized: "\(leg.displayName) departure is delayed by \(Format.durationInline(real - planned))")
                    )
                }
            case let .arrivalDelayed(leg):
                guard let real = leg.arrival, let planned = leg.plannedArrival else { continue }
                let delay = (real - planned).minutes
                if delay - notifyStatus.arrivalDelays[leg.stableID, default: 0] >= 5 {
                    notifyStatus.arrivalDelays[leg.stableID] = delay
                    Notifier.send(
                        id: "railway-leg-arrival-delayed-\(leg.stableID)",
                        title: String(localized: "\(leg.displayName) arrival is delayed by \(Format.durationInline(real - planned))")
                    )
                }
            case let .departurePlatformChange(leg):
                guard let platform = leg.departurePlatform,
                      notifyStatus.departurePlatformChanges[leg.stableID] != platform else { continue }
                notifyStatus.departurePlatformChanges[leg.stableID] = platform
                Notifier.send(
                    id: "railway-leg-departure-platform-changed-\(leg.stableID)",
                    title: String(localized: "\(leg.displayName) departing on platform \(platform) today instead")
                )
            case let .legUnreachable(leg):
                guard notifyStatus.unreachable.insert(leg.stableID).inserted else { continue }
                Notifier.send(
                    id: "railway-leg-unreachable-\(leg.stableID)",
                    title: String(localized: "Warning: No longer possible to reach connecting \(leg.displayName) from \(leg.origin.name) to \(leg.destination.name).")
                )
            case let .legCancelled(leg):
                guard notifyStatus.cancelled.insert(leg.stableID).inserted else { continue }
                Notifier.send(
                    id: "railway-leg-cancelled-\(leg.stableID)",
                    title: String(localized: "Warning: \(leg.displayName) from \(leg.origin.name) to \(leg.destination.name) was cancelled.")
                )
            }
        }
    }
}

/// Keeps a single `JourneyModel` per journey id.
@MainActor
final class JourneyRegistry {
    private var models: [String: JourneyModel] = [:]

    /// A journey seen before in this session (or bookmarked), e.g. to restore a trip window.
    func existing(id: String) -> JourneyModel? {
        models[id]
    }

    func model(for journey: Journey, providerID: String) -> JourneyModel {
        if let existing = models[journey.id] {
            existing.update(journey)
            return existing
        }
        let model = JourneyModel(journey: journey, providerID: providerID)
        models[journey.id] = model
        return model
    }
}

/// Sends user notifications.
enum Notifier {
    static func requestAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    static func send(id: String, title: String, body: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
