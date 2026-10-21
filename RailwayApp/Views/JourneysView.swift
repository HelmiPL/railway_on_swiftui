import SwiftUI

/// The middle column: connections found for the search. Ported from Railway's `JourneysPage`.
struct JourneysView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    /// The title's natural width and the column's, so the title only shortens when it must.
    @State private var titleWidth: CGFloat = 0
    @State private var columnWidth: CGFloat = 0

    /// What the toolbar leaves for the title: the column, less its margins, the other items with
    /// the space iPadOS puts around each, and some slack. Any less and iPadOS moves all items into
    /// a "…" menu (measured in a 390 pt column: 172 pt is the most the title can have with the
    /// replaced sidebar button and the bookmark button).
    private var availableTitleWidth: CGFloat {
        var items: [CGFloat] = []
        if model.replacesSidebarToggle { items += [30, 44] }
        if model.result != nil { items.append(44) }
        let width = columnWidth - 2 * 16 - titleLeadingPadding
            - items.reduce(0, +) - CGFloat(items.count) * 12 - 32
        return max(width, 60)
    }

    /// As far from the column's edge as the title is from the top and bottom of the toolbar
    /// (it is centred in it, 25 pt from either); after the sidebar button, the usual spacing.
    private var titleLeadingPadding: CGFloat {
        model.replacesSidebarToggle ? 0 : 13.5
    }
    #endif

    private var title: String {
        model.result.map { "\($0.source.name) → \($0.destination.name)" } ?? String(localized: "Railway")
    }

    var body: some View {
        Group {
            if let result = model.result {
                JourneysList(result: result)
            } else {
                ContentUnavailableView {
                    Label("Search for Trips", systemImage: "magnifyingglass")
                } description: {
                    Text("Choose a start and a destination to see connections.")
                }
            }
        }
        // The rhwooute names the window and its tab.
        .navigationTitle(title)
        #if os(iOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
        // Small and on the left, like the title of the column on the Mac. iPadOS centres inline
        // titles, so the title is shown as a toolbar item instead; it still names the window.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        // The system's sidebar button is replaced below, after the full-screen close button.
        .toolbar(removing: model.replacesSidebarToggle ? .sidebarToggle : nil)
        .toolbar {
            if model.replacesSidebarToggle {
                // Room for the full-screen close button in the window's corner, then the sidebar
                // button the system would have put there.
                ToolbarItem(placement: .topBarLeading) {
                    Color.clear.frame(width: 30, height: 1)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.toggleSidebar()
                    } label: {
                        Label("Show Sidebar", systemImage: "sidebar.left")
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // Toolbar items are otherwise squeezed to a few letters: as wide as the title,
                    // or as the toolbar allows, so it doesn't push the other items into a menu.
                    .frame(width: titleWidth > 0 ? min(titleWidth, availableTitleWidth) : nil)
                    .background {
                        Text(title)
                            .font(.headline)
                            .fixedSize()
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
                    }
                    .padding(.leading, titleLeadingPadding)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: {
                        model.toolbarCentreY = $0
                    }
                    .accessibilityAddTraits(.isHeader)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        #endif
        .toolbar {
            if model.result != nil {
                ToolbarItem {
                    Button {
                        model.toggleResultBookmark()
                    } label: {
                        Label(
                            model.isResultBookmarked ? "Remove Search Bookmark" : "Bookmark This Search",
                            systemImage: model.isResultBookmarked ? "bookmark.fill" : "bookmark"
                        )
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: model.isResultBookmarked)
                    }
                    .help(model.isResultBookmarked ? "Remove Search Bookmark" : "Bookmark This Search")
                }
            }
        }
    }
}

/// The connections, styled like a native Mail-style list: accent selection, faint hover highlight
/// and arrow-key navigation.
private struct JourneysList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focused: Bool
    var result: JourneysResult

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                JourneyRows(result: result) { journey in
                    model.open(journey)
                    focused = true
                    #if os(macOS)
                    // Without room for the details, show the trip in its own window.
                    if model.isCompact {
                        openWindow(id: SceneID.trip, value: journey.id)
                    }
                    #endif
                }
            }
            #if os(iOS)
            .refreshable { await model.reloadResults() }
            #endif
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            #if os(macOS)
            .onMoveCommand { direction in
                move(direction)
                if let id = model.selectedJourney?.id {
                    withAnimation(.snappy) { proxy.scrollTo(id) }
                }
            }
            #endif
            .onChange(of: result.journeys.first?.id) { old, new in
                // Keep the previously first journey in view after prepending earlier ones.
                if let old, old != new { proxy.scrollTo(old, anchor: .top) }
            }
        }
    }

    #if os(macOS)
    private func move(_ direction: MoveCommandDirection) {
        let journeys = result.journeys
        guard !journeys.isEmpty else { return }
        let current = journeys.firstIndex { $0.id == model.selectedJourney?.id }
        let next: Int = switch (direction, current) {
        case (.up, let index?): max(index - 1, 0)
        case (.down, let index?): min(index + 1, journeys.count - 1)
        case (.up, nil): journeys.count - 1
        default: 0
        }
        model.selectedJourney = journeys[next]
    }
    #endif
}

/// The connections grouped by day, with buttons to load earlier and later ones.
///
/// The Mac shows them in their own column; iOS/iPadOS shows them below the search form.
struct JourneyRows: View {
    @Environment(AppModel.self) private var model
    var result: JourneysResult
    /// Whether the selected journey is highlighted; on iOS/iPadOS it opens in a sheet instead.
    var highlightsSelection = true
    var onSelect: (JourneyModel) -> Void

    var body: some View {
        let days = result.days
        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
            LoadMoreRow(title: "Earlier Connections", systemImage: "arrow.up", loading: model.loadingEarlier) {
                model.loadEarlier()
            }
            .disabled(result.earlierRef == nil)

            ForEach(Array(days.enumerated()), id: \.element.day) { index, day in
                Section {
                    ForEach(Array(day.journeys.enumerated()), id: \.element.id) { position, journey in
                        let selected = isSelected(journey)
                        let previousSelected = position > 0 && isSelected(day.journeys[position - 1])
                        JourneyListRow(
                            journey: journey,
                            isSelected: selected,
                            showsSeparator: position > 0 && !selected && !previousSelected
                        ) {
                            onSelect(journey)
                        }
                        .id(journey.id)
                        .onAppear {
                            // Load more when reaching the end of the list, like Railway.
                            if journey.id == result.journeys.last?.id {
                                model.loadLater()
                            }
                        }
                        .contextMenu { JourneyContextMenu(journey: journey) }
                    }
                } header: {
                    // The requested day needs no header at the very top.
                    if index > 0 || !Calendar.current.isDate(day.day, inSameDayAs: result.requestedTime) {
                        DayHeader(day: day.day)
                    }
                }
            }

            LoadMoreRow(title: "Later Connections", systemImage: "arrow.down", loading: model.loadingLater) {
                model.loadLater()
            }
            .disabled(result.laterRef == nil)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func isSelected(_ journey: JourneyModel) -> Bool {
        highlightsSelection && model.selectedJourney?.id == journey.id
    }
}

/// A day divider that stays pinned while scrolling.
private struct DayHeader: View {
    var day: Date

    var body: some View {
        Text(Format.day(day))
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct JourneyListRow: View {
    var journey: JourneyModel
    var isSelected: Bool
    var showsSeparator: Bool
    var onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        JourneyRow(journey: journey)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .environment(\.backgroundProminence, isSelected ? .increased : .standard)
            .background {
                // Two layers that only change opacity, so switching never blends through other colours.
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(hovering && !isSelected ? 0.06 : 0))
                        .animation(.easeOut(duration: 0.12), value: hovering)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(isSelected ? 1 : 0))
                }
            }
            .overlay(alignment: .top) {
                Divider()
                    .padding(.horizontal, 10)
                    .opacity(showsSeparator && !hovering ? 1 : 0)
            }
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .onTapGesture(perform: onSelect)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onSelect)
    }
}

private struct LoadMoreRow: View {
    var title: LocalizedStringKey
    var systemImage: String
    var loading: Bool
    var action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .font(.callout)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(height: 40)
    }
}
/// One connection in the list, ported from Railway's `JourneyListItem`.
struct JourneyRow: View {
    var journey: JourneyModel

    var body: some View {
        let j = journey.journey
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                TimeLabel(planned: j.firstLeg?.plannedDeparture, real: j.firstLeg?.departure, style: .prominent)
                durationLine(j)
                TimeLabel(planned: j.lastLeg?.plannedArrival, real: j.lastLeg?.arrival, style: .prominent)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(j.originName).lineLimit(1)
                Spacer(minLength: 12)
                Text(j.destinationName).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ModeStrip(legs: j.legs)
                IndicatorIcons(journey: j)
                Spacer(minLength: 6)
                if let price = j.price {
                    Text(Format.price(price))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 7)
        .opacity(j.isCancelled || j.isUnreachable ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription(j))
    }

    private func durationLine(_ j: Journey) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(.tertiary).frame(height: 1.5)
            if let total = j.totalTime {
                Text(Format.durationTabular(total))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if j.transitions > 0 {
                Text("\(j.transitions)×")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: .capsule)
                    .help("^[\(j.transitions) change](inflect: true)")
                    .fixedSize()
            }
            Capsule().fill(.tertiary).frame(height: 1.5)
        }
    }

    private func accessibilityDescription(_ j: Journey) -> Text {
        let departure = Format.time(j.firstLeg?.departure ?? j.firstLeg?.plannedDeparture) ?? ""
        let arrival = Format.time(j.lastLeg?.arrival ?? j.lastLeg?.plannedArrival) ?? ""
        let travelTime = j.totalTime.map(Format.durationTabular) ?? ""
        return Text("From \(j.originName) at \(departure) to \(j.destinationName) at \(arrival), \(travelTime), ^[\(j.transitions) change](inflect: true). \(j.types)")
    }
}

/// The products used by a journey as small coloured icons with their names.
private struct ModeStrip: View {
    var legs: [Leg]
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(legs.filter { !$0.walking }.enumerated()), id: \.offset) { index, leg in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 2) {
                    Image(systemName: leg.inferredMode.systemImage)
                        .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(leg.inferredMode.tint))
                    Text(leg.line?.productName ?? leg.line?.product.short ?? "")
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .layoutPriority(-1)
    }
}

/// Actions on a journey, shared by context menus.
struct JourneyContextMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    var journey: JourneyModel

    var body: some View {
        let bookmarked = model.journeyStore.contains(journey)
        if supportsMultipleWindows {
            Button("Open in New Window", systemImage: "macwindow.badge.plus") {
                openWindow(id: SceneID.trip, value: journey.id)
            }
            Divider()
        }
        Button(bookmarked ? "Remove Bookmark" : "Bookmark This Trip",
               systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
            model.toggleBookmark(journey)
        }
        Button("Refresh This Trip", systemImage: "arrow.clockwise") {
            model.refresh(journey)
        }
    }
}
