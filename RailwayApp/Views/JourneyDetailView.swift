import SwiftUI

/// The detail column: one trip with all its legs. Ported from Railway's `JourneyDetailPage`.
struct JourneyDetailView: View {
    @Environment(AppModel.self) private var model
    /// Trip windows are titled with the route instead of "Trip Details".
    var showsRouteAsTitle = false

    private var title: String {
        guard let journey = model.selectedJourney?.journey else { return "" }
        return showsRouteAsTitle ? "\(journey.originName) → \(journey.destinationName)" : String(localized: "Trip Details")
    }

    var body: some View {
        Group {
            if let journey = model.selectedJourney {
                JourneyDetail(journey: journey, isWatched: model.journeyStore.isWatched(journey))
                    .id(journey.id)
            } else if showsRouteAsTitle {
                ContentUnavailableView {
                    Label("Trip Not Available", systemImage: "tram.fill")
                } description: {
                    Text("Search for the connection again to see its details.")
                }
            } else {
                ContentUnavailableView {
                    Label("Choose a Trip", systemImage: "tram.fill")
                } description: {
                    Text("Select a connection to see its stops, platforms and announcements.")
                }
            }
        }
        .navigationTitle(title)
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let journey = model.selectedJourney {
            let bookmarked = model.journeyStore.contains(journey)
            let watched = model.journeyStore.isWatched(journey)
            ToolbarItem {
                Button {
                    model.refresh(journey)
                } label: {
                    if journey.refreshInProgress {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh This Trip", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(journey.refreshInProgress)
                .help("Refresh This Trip")
            }

            ToolbarSpacer(.fixed)

            ToolbarItemGroup {
                if bookmarked {
                    Button {
                        model.toggleWatch(journey)
                    } label: {
                        Label(watched ? "Stop Watching This Trip" : "Watch This Trip",
                              systemImage: watched ? "bell.fill" : "bell")
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.wiggle, value: watched)
                    }
                    .help(watched ? "Stop Watching This Trip" : "Watch This Trip and Get Notified About Changes")
                    }

                Button {
                    model.toggleBookmark(journey)
                } label: {
                    Label(bookmarked ? "Remove Bookmark" : "Bookmark This Trip",
                          systemImage: bookmarked ? "bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: bookmarked)
                }
                .help(bookmarked ? "Remove Bookmark" : "Bookmark This Trip")
            }
        }
    }
}

private struct JourneyDetail: View {
    @Environment(AppModel.self) private var model
    var journey: JourneyModel
    var isWatched: Bool

    var body: some View {
        let j = journey.journey
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(j.originName) → \(j.destinationName)")
                        .font(.largeTitle.weight(.bold))
                        .padding(.bottom, 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            if let total = j.totalTime {
                                InfoChip(Format.durationTabular(total), systemImage: "clock")
                                    .help("Total Travel Time")
                            }
                            if let departure = j.departure {
                                InfoChip(Format.day(departure.date), systemImage: "calendar")
                            }
                            if j.transitions > 0 {
                                InfoChip(String(AttributedString(localized: "^[\(j.transitions) change](inflect: true)").characters), systemImage: "arrow.triangle.swap")
                            }
                            if let price = j.price {
                                InfoChip(Format.price(price), systemImage: "creditcard")
                            }
                        }
                    }
                    Text("Last refreshed \(Format.time(journey.lastRefreshed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(segments(of: j.legs)) { segment in
                        switch segment.kind {
                        case let .leg(leg):
                            LegCard(leg: leg)
                        case let .transition(transition):
                            TransitionRow(transition: transition)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Trip Segments")
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.top)
        .background { TripGradient(legs: j.legs) }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isWatched {
                LiveBanner(journey: journey)
            }
        }
        .onChange(of: isWatched, initial: true) { _, watched in
            // While the live banner is visible, keep the trip up to date every minute.
            if watched {
                model.tracker.registerMinutely(journey)
            } else {
                model.tracker.unregisterMinutely(journey)
            }
        }
        .onDisappear {
            model.tracker.unregisterMinutely(journey)
        }
    }
}

/// What is happening right now on a watched trip.
private struct LiveBanner: View {
    var journey: JourneyModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let event = journey.event(at: context.date)
            Label {
                Text(event.description(at: context.date))
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: event != .afterJourney)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.tint(.accentColor.opacity(0.25)), in: .capsule)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// A small piece of information about the trip, on glass.
private struct InfoChip: View {
    var title: String
    var systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }
}

/// A soft background made from the colours of the trains used: glowing blobs drifting over a
/// gradient, like an aurora. Can be stilled in Settings, and is still with Reduce Motion.
private struct TripGradient: View {
    var legs: [Leg]
    @AppStorage(SettingsKey.animateBackground) private var animate = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private struct Blob {
        var color: Color
        /// Angular speeds of the horizontal and vertical motion, in radians per second.
        var speed: (x: Double, y: Double)
        var phase: Double
    }

    private var tints: [Color] {
        let tints = legs.filter { !$0.walking }.map(\.inferredMode.tint)
        return tints.isEmpty ? [.accentColor] : tints
    }

    private var strength: Double { colorScheme == .dark ? 0.55 : 0.4 }

    private var blobs: [Blob] {
        let tints = tints
        // Three to four blobs, cycling through the trains in order of the trip.
        let count = max(3, min(tints.count, 4))
        return (0..<count).map { index in
            Blob(
                color: tints[index % tints.count],
                speed: (0.23 + 0.07 * Double(index), 0.31 - 0.05 * Double(index)),
                phase: Double(index) * 2.1
            )
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: (tints.count == 1 ? tints + tints : tints).map { $0.opacity(strength * 0.45) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if animate && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    aurora(time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                aurora(time: 0)
            }
            // Fade out towards the bottom, so long trips stay calm.
            LinearGradient(
                colors: [.clear, Color(nsColor: .windowBackgroundColor).opacity(0.45)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func aurora(time t: Double) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let diameter = max(size.width, size.height) * 0.95
            ZStack {
                ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                    Circle()
                        .fill(RadialGradient(
                            colors: [blob.color.opacity(strength), blob.color.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter / 2
                        ))
                        .frame(width: diameter, height: diameter)
                        .position(
                            x: size.width * (0.5 + 0.45 * sin(t * blob.speed.x + blob.phase)),
                            y: size.height * (0.35 + 0.35 * cos(t * blob.speed.y + blob.phase * 1.7))
                        )
                }
            }
            .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        }
    }
}

// MARK: - Segments

/// A change between legs, possibly involving walking.
struct Transition: Hashable {
    var walkingTime: Duration?
    var waitingTime: Duration?
    var hasWalk: Bool
    var isLastMile: Bool
    var finalDestination: String?

    var systemImage: String {
        hasWalk || isLastMile ? "figure.walk" : "arrow.triangle.swap"
    }

    var label: String {
        switch (walkingTime.map(Format.durationInline), waitingTime.map(Format.durationInline)) {
        case let (walk?, wait?): String(localized: "Walk \(walk) Wait \(wait)")
        case let (nil, wait?): String(localized: "Transfer Time \(wait)")
        case let (walk?, nil): String(localized: "Walk \(walk)")
        case (nil, nil): String(localized: "Transfer")
        }
    }
}

private struct Segment: Identifiable {
    enum Kind {
        case leg(Leg)
        case transition(Transition)
    }

    var id: Int
    var kind: Kind
}

/// Folds walking legs into transitions between the vehicle legs, like Railway's detail page.
private func segments(of legs: [Leg]) -> [Segment] {
    var result: [Segment] = []
    var i = 0
    while i < legs.count {
        var walkingTime: Duration?
        let isStart = i == 0
        let startIndex = i
        var to = legs[i]
        while to.walking {
            let walked = to.arrival.map { arrival in arrival - (to.departure ?? arrival) } ?? .zero
            walkingTime = (walkingTime ?? .zero) + walked
            i += 1
            if i < legs.count { to = legs[i] } else { break }
        }
        let isEnd = i == legs.count
        var waitingTime: Duration?
        if !isStart, !isEnd, let departure = to.departure, let arrival = legs[i - 1].arrival {
            waitingTime = departure - arrival
        }
        if walkingTime != nil || !isStart {
            let transition = Transition(
                walkingTime: walkingTime,
                waitingTime: waitingTime,
                hasWalk: walkingTime != nil || (!isEnd && to.origin != legs[startIndex].origin),
                isLastMile: isStart || isEnd,
                finalDestination: isEnd ? to.destination.name : nil
            )
            result.append(Segment(id: result.count, kind: .transition(transition)))
        }
        if !isEnd {
            result.append(Segment(id: result.count, kind: .leg(to)))
        }
        i += 1
    }
    return result
}

// MARK: - Layout constants

/// Shared geometry so the timeline lines up across rows.
private enum Timeline {
    static let timeWidth: CGFloat = 58
    static let railWidth: CGFloat = 26
    static let spacing: CGFloat = 8
    static let railThickness: CGFloat = 4
}

private struct TransitionRow: View {
    var transition: Transition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            capsule {
                Image(systemName: transition.systemImage)
                    .foregroundStyle(.secondary)
                Text(transition.label)
                    .foregroundStyle(.secondary)
            }
            if let destination = transition.finalDestination {
                capsule {
                    Image(systemName: "flag.checkered")
                    Text(destination).fontWeight(.semibold)
                }
            }
        }
        .font(.callout)
        // Centre the icons on the timeline of the leg cards.
        .padding(.leading, 14 + Timeline.timeWidth + Timeline.spacing + Timeline.railWidth / 2 - 18)
        .accessibilityElement(children: .combine)
    }

    private func capsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .fixedSize()
    }
}

// MARK: - Leg

/// One vehicle leg, ported from Railway's `LegItem`.
private struct LegCard: View {
    var leg: Leg
    #if DEBUG
    @State private var showStops = DebugAutomation.expand
    @State private var showRemarks = DebugAutomation.expand
    #else
    @State private var showStops = false
    @State private var showRemarks = false
    #endif

    private var tint: Color { leg.inferredMode.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StationRow(
                time: TimeLabel(planned: leg.plannedDeparture, real: leg.departure, axis: .vertical),
                node: .start, tint: tint, name: leg.origin.name,
                platform: PlatformLabel(planned: leg.plannedDeparturePlatform, real: leg.departurePlatform)
            )

            RailRow(tint: tint) { details }

            if showStops {
                ForEach(Array(leg.intermediateStops.enumerated()), id: \.offset) { _, location in
                    IntermediateRow(location: location, tint: tint)
                }
                .transition(.opacity)
            }

            StationRow(
                time: TimeLabel(planned: leg.plannedArrival, real: leg.arrival, axis: .vertical),
                node: .end, tint: tint, name: leg.destination.name,
                platform: PlatformLabel(planned: leg.plannedArrivalPlatform, real: leg.arrivalPlatform)
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .opacity(leg.cancelled ? 0.6 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(leg.displayName)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                LineBadge(leg: leg)
                if let direction = leg.direction {
                    Text("to \(direction)")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(leg.displayName) in the direction of \(leg.direction ?? "")"))

            if let frequency = leg.averageFrequency {
                Label("every ~\(Format.durationInline(frequency))", systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if leg.cancelled {
                Label("Cancelled", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.callout.weight(.semibold))
            } else if !leg.reachable {
                Label("Connection Not Possible", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout.weight(.semibold))
            }

            HStack(spacing: 8) {
                if !leg.intermediateStops.isEmpty {
                    Button {
                        withAnimation(.snappy) { showStops.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("^[\(leg.stopCount) Stop](inflect: true)")
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(showStops ? 90 : 0))
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("Show Intermediate Stops")
                }
                Spacer(minLength: 0)
                IndicatorIcons(leg: leg)
                if !leg.remarks.isEmpty {
                    Toggle(isOn: $showRemarks.animation(.snappy)) {
                        Label("Show Announcements", systemImage: "info.circle")
                            .labelStyle(.iconOnly)
                    }
                    .toggleStyle(.button)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help("Show Announcements")
                }
            }

            if showRemarks {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(leg.remarks.enumerated()), id: \.offset) { _, remark in
                        RemarkRow(remark: remark)
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Announcements")
            }
        }
        .padding(.vertical, 10)
    }
}

private enum RailNode { case start, end, stop, pass }

/// Draws a piece of the vertical line, optionally with a station marker in the middle.
private struct RailSegment: View {
    var node: RailNode?
    var tint: Color

    var body: some View {
        GeometryReader { geometry in
            let midX = geometry.size.width / 2
            let midY = geometry.size.height / 2
            ZStack {
                Path { path in
                    let top: CGFloat = node == .start ? midY : 0
                    let bottom: CGFloat = node == .end ? midY : geometry.size.height
                    path.move(to: CGPoint(x: midX, y: top))
                    path.addLine(to: CGPoint(x: midX, y: bottom))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: Timeline.railThickness, lineCap: .round))

                switch node {
                case .start, .end:
                    Circle()
                        .fill(.background)
                        .stroke(tint, lineWidth: 3.5)
                        .frame(width: 15, height: 15)
                        .position(x: midX, y: midY)
                case .stop:
                    Circle()
                        .fill(.background)
                        .stroke(tint, lineWidth: 2)
                        .frame(width: 9, height: 9)
                        .position(x: midX, y: midY)
                case .pass, nil:
                    EmptyView()
                }
            }
        }
        .frame(width: Timeline.railWidth)
        .accessibilityHidden(true)
    }
}

private struct StationRow: View {
    var time: TimeLabel
    var node: RailNode
    var tint: Color
    var name: String
    var platform: PlatformLabel

    var body: some View {
        HStack(spacing: Timeline.spacing) {
            time
                .frame(width: Timeline.timeWidth, alignment: .trailing)
            Color.clear.frame(width: Timeline.railWidth)
            Text(name)
                .font(.headline)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            platform
        }
        .frame(minHeight: 30)
        .background(alignment: .leading) {
            RailSegment(node: node, tint: tint)
                .padding(.leading, Timeline.timeWidth + Timeline.spacing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row continuing the rail without a station, holding arbitrary content.
private struct RailRow<Content: View>: View {
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Timeline.spacing) {
            Color.clear.frame(width: Timeline.timeWidth, height: 1)
            Color.clear.frame(width: Timeline.railWidth, height: 1)
            content
        }
        .background(alignment: .leading) {
            RailSegment(node: nil, tint: tint)
                .padding(.leading, Timeline.timeWidth + Timeline.spacing)
        }
    }
}

/// A stop between the origin and destination of a leg, ported from `IntermediateLocationItem`.
private struct IntermediateRow: View {
    var location: IntermediateLocation
    var tint: Color

    var body: some View {
        switch location {
        case let .stop(stop):
            HStack(spacing: Timeline.spacing) {
                TimeLabel(planned: stop.plannedArrival ?? stop.plannedDeparture,
                          real: stop.arrival ?? stop.departure, style: .small)
                    .frame(width: Timeline.timeWidth, alignment: .trailing)
                Color.clear.frame(width: Timeline.railWidth)
                Text(stop.place.name)
                    .font(.callout)
                    .strikethrough(stop.cancelled)
                    .foregroundStyle(stop.cancelled ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                PlatformLabel(planned: stop.plannedDeparturePlatform, real: stop.departurePlatform)
                    .font(.caption)
            }
            .frame(minHeight: 26)
            .background(alignment: .leading) {
                RailSegment(node: .stop, tint: tint)
                    .padding(.leading, Timeline.timeWidth + Timeline.spacing)
            }
            .accessibilityElement(children: .combine)
        case let .railway(place):
            HStack(spacing: Timeline.spacing) {
                Color.clear.frame(width: Timeline.timeWidth)
                Color.clear.frame(width: Timeline.railWidth)
                Text(place.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 22)
            .background(alignment: .leading) {
                RailSegment(node: .pass, tint: tint)
                    .padding(.leading, Timeline.timeWidth + Timeline.spacing)
            }
        }
    }
}

private struct RemarkRow: View {
    var remark: Remark

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: remark.type == .status ? "exclamationmark.bubble" : remark.association.systemImage)
                .foregroundStyle(remark.type == .status ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            Text(remark.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
