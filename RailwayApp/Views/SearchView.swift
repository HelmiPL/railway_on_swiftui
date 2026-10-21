import SwiftUI

/// The sidebar: where to go, when, and bookmarks. Ported from Railway's `SearchPage`.
///when hoverin 
/// Everything here sits on the control layer, so it uses Liquid Glass, grouped in containers so
/// neighbouring elements blend and morph together.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focusedField: FieldKind?
    @State private var showingOptions = false
    /// Whether the search options differ from the defaults, shown as a red dot on their button.
    @State private var optionsCustomized = SearchOptions.load().isCustomized
    /// Frames of the fields inside the route panel.
    @State private var fieldFrames: [FieldKind: CGRect] = [:]
    /// The route panel's position in the window, so the suggestions follow it.
    @State private var routeFrame = CGRect.zero

    enum FieldKind { case from, to }

    nonisolated static let coordinateSpace = "route"

    private var activeField: StationField? {
        switch focusedField {
        case .from: model.from
        case .to: model.to
        case nil: nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                routePanel
                TimeControls()
                searchButton
                BookmarkLists()
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Railway")
        .toolbar {
            // These belong to the search form; with the sidebar hidden AppKit would otherwise move
            // them into the toolbar's overflow menu.
            if model.isSidebarVisible {
                ToolbarItem {
                    ProviderButton()
                }
                // Keep the options button out of the network picker's glass capsule.
                ToolbarSpacer(.fixed)
                ToolbarItem {
                    Button {
                        showingOptions = true
                    } label: {
                        Label(SearchOptionsButton.title, systemImage: "slider.horizontal.3")
                    }
                    .help(SearchOptionsButton.help)
                    // An empty badge is the native, text-less red indicator.
                    .badge(optionsCustomized ? Text(verbatim: "") : nil)
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            SearchOptionsSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let customized = SearchOptions.load().isCustomized
            if customized != optionsCustomized { optionsCustomized = customized }
        }
        .onChange(of: model.focusFromRequest) {
            focusedField = .from
        }
        #if DEBUG
        .task {
            // See DebugAutomation: type into the "From" field.
            if ProcessInfo.processInfo.environment["RAILWAY_OPTIONS"] != nil {
                try? await Task.sleep(for: .seconds(1))
                showingOptions = true
            }
            if let text = ProcessInfo.processInfo.environment["RAILWAY_TYPE"] {
                try? await Task.sleep(for: .seconds(1))
                focusedField = .from
                model.from.edit(text)
            }
        }
        #endif
    }

    // MARK: Route

    private var routePanel: some View {
        VStack(spacing: 0) {
            stationField(model.from, title: "From", systemImage: "circle.circle", kind: .from)
            // Stops short of the swap icon, leaving it some room.
            Divider().padding(.leading, 40).padding(.trailing, 14)
            stationField(model.to, title: "To", systemImage: "mappin.circle", kind: .to)
        }
        // Room for the swap icon on the right.
        .padding(.trailing, 30)
        .overlay(alignment: .trailing) {
            SwapIcon {
                withAnimation(.bouncy) { model.swapPlaces() }
            }
            .padding(.trailing, 8)
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { routeFrame = $0 }
        .background { suggestionPanel }
    }

    private func stationField(_ field: StationField, title: LocalizedStringKey, systemImage: String, kind: FieldKind) -> some View {
        StationTextField(field: field, title: title, systemImage: systemImage, focus: $focusedField, kind: kind) {
            advanceFocus()
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.coordinateSpace)) } action: {
            fieldFrames[kind] = $0
        }
    }

    /// Autocompletion floating below the focused field, like the search suggestions in Music.
    private var suggestionPanel: some View {
        SuggestionPanelAnchor(
            field: activeField,
            topOffset: focusedField.flatMap { fieldFrames[$0]?.maxY }.map { $0 + 4 } ?? 0,
            anchorFrame: routeFrame
        ) { place in
            activeField?.select(place)
            advanceFocus()
        }
    }

    private func advanceFocus() {
        if focusedField == .from, !model.to.isSet {
            focusedField = .to
        } else {
            focusedField = nil
        }
    }

    // MARK: Options and search

    private var searchButton: some View {
        Button {
            focusedField = nil
            model.search()
        } label: {
            ZStack {
                Label("Search", systemImage: "magnifyingglass")
                    .fontWeight(.semibold)
                    .opacity(model.searching ? 0 : 1)
                if model.searching {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .disabled(!model.canSearch)
        .keyboardShortcut(.defaultAction)
        .help(model.searchUnavailableReason.map { Text($0) } ?? Text("Search for Connections"))
        .padding(.top, 2)
    }
}

// MARK: - Station fields

/// A "From" or "To" text field that resolves to a place.
private struct StationTextField: View {
    @Bindable var field: StationField
    var title: LocalizedStringKey
    var systemImage: String
    var focus: FocusState<SearchView.FieldKind?>.Binding
    var kind: SearchView.FieldKind
    var onSelect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: field.isSet ? systemImage + ".fill" : systemImage)
                .symbolRenderingMode(field.isSet ? .monochrome : .hierarchical)
                .foregroundStyle(field.isSet ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .font(.title3)
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            TextField(title, text: Binding(get: { field.text }, set: { field.edit($0) }))
                .textFieldStyle(.plain)
                .focused(focus, equals: kind)
                .onKeyPress(.downArrow) {
                    guard !field.suggestions.isEmpty else { return .ignored }
                    field.moveHighlight(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !field.suggestions.isEmpty else { return .ignored }
                    field.moveHighlight(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    if field.selectHighlighted() {
                        onSelect()
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    guard !field.suggestions.isEmpty else { return .ignored }
                    field.dismissSuggestions()
                    return .handled
                }
            if field.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .transition(.opacity)
            } else if !field.text.isEmpty, focus.wrappedValue == kind {
                Button {
                    field.edit("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(.rect)
        .onTapGesture { focus.wrappedValue = kind }
        .animation(.default, value: field.isLoading)
    }
}

// MARK: - Time

/// Departure/arrival and when, ported from Railway's `DateTimePicker`.
/// The swap button inside the route panel: just the icon, highlighting on hover.
private struct SwapIcon: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.body.weight(.medium))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Swap Start and Destination")
        .accessibilityLabel("Swap Start and Destination")
    }
}

/// Departure/arrival, date and time as one group, ported from Railway's `DateTimePicker`.
private struct TimeControls: View {
    @Environment(AppModel.self) private var model
    @State private var showingDate = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            NativeSegmentedControl(selection: $model.timeType, options: [
                (.departure, String(localized: "Departure")),
                (.arrival, String(localized: "Arrival")),
            ])
            .accessibilityLabel("Time Type")
            // Inset enough to sit clear of the panel's rounded corners.
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 12)

            TimelineView(.everyMinute) { _ in
                HStack(spacing: 8) {
                    GroupRowButton {
                        showingDate = true
                    } label: {
                        Label(model.useNow ? Format.day(.now) : Format.day(model.date), systemImage: "calendar")
                    }
                    .popover(isPresented: $showingDate, arrowEdge: .bottom) { datePopover }
                    .help("Choose the Day")

                    Spacer(minLength: 4)

                    // Click the hours or the minutes and type, like everywhere else in macOS.
                    DatePicker("Time", selection: dateBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .fixedSize()
                        .help("Type the Hour and Minutes")

                    Toggle("Now", isOn: nowBinding)
                        .toggleStyle(.button)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .help("Search from the Current Time")
                }
                // Line up with the switch above: "Now" ends where it ends, and the day's icon
                // starts where it starts (the day button has its own inner padding for hovering).
                .padding(.leading, 4)
                .padding(.trailing, 12)
                .padding(.top, 6)
                .padding(.bottom, 9)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Changing the date or time stops following the current time.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { model.useNow ? .now : model.date },
            set: {
                model.date = $0
                model.useNow = false
            }
        )
    }

    private var nowBinding: Binding<Bool> {
        Binding(
            get: { model.useNow },
            set: { useNow in
                if !useNow { model.date = .now }
                model.useNow = useNow
            }
        )
    }

    private var datePopover: some View {
        VStack(spacing: 10) {
            DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            Button("Today") {
                let calendar = Calendar.current
                let now = Date.now
                let time = calendar.dateComponents([.hour, .minute], from: model.useNow ? now : model.date)
                model.date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: now) ?? now
                showingDate = false
            }
            .buttonStyle(.glass)
        }
        .padding(14)
    }
}

/// A borderless button inside a grouped glass panel, highlighting on hover.
private struct GroupRowButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(hovering ? 0.08 : 0), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Bookmarks

/// Bookmarked trips and searches, in collapsible sections like a Finder sidebar.
private struct BookmarkLists: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("sidebar-trips-expanded") private var tripsExpanded = true
    @AppStorage("sidebar-searches-expanded") private var searchesExpanded = true

    var body: some View {
        if !model.journeyStore.journeys.isEmpty {
            BookmarkSection(title: "Bookmarked Trips", isExpanded: $tripsExpanded) {
                ForEach(model.journeyStore.journeys) { journey in
                    BookmarkRow(isSelected: model.selectedJourney?.id == journey.id) {
                        model.selectedJourney = journey
                        if model.isCompact {
                            openWindow(id: SceneID.trip, value: journey.id)
                        }
                    } label: {
                        JourneyBookmarkLabel(journey: journey, isWatched: model.journeyStore.isWatched(journey))
                    }
                    .contextMenu {
                        Button("Open in New Window", systemImage: "macwindow.badge.plus") {
                            openWindow(id: SceneID.trip, value: journey.id)
                        }
                        Divider()
                        Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
                            model.journeyStore.remove(journey)
                        }
                    }
                }
            }
        }
        if !model.searchStore.searches.isEmpty {
            BookmarkSection(title: "Bookmarked Searches", isExpanded: $searchesExpanded) {
                ForEach(model.searchStore.searches) { search in
                    BookmarkRow(isSelected: false) {
                        model.run(search)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text("\(search.origin) → \(search.destination)")
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .help("Search from \(search.origin) to \(search.destination)")
                    .contextMenu {
                        Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
                            model.searchStore.remove(search)
                        }
                    }
                }
            }
        }
    }
}

private struct BookmarkSection<Content: View>: View {
    var title: LocalizedStringKey
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(hovering ? 1 : 0)
                }
                .padding(.horizontal, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            .padding(.top, 10)

            if isExpanded {
                VStack(spacing: 0) { content }
                    .padding(5)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }
}

private struct JourneyBookmarkLabel: View {
    var journey: JourneyModel
    var isWatched: Bool

    var body: some View {
        let journey = journey.journey
        HStack(spacing: 10) {
            Image(systemName: isWatched ? "bell.fill" : "tram.fill")
                .foregroundStyle(isWatched ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 30)), isActive: isWatched)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TimeLabel(planned: journey.firstLeg?.plannedDeparture, real: journey.firstLeg?.departure, style: .small)
                    Text(journey.originName).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TimeLabel(planned: journey.lastLeg?.plannedArrival, real: journey.lastLeg?.arrival, style: .small)
                    Text(journey.destinationName).lineLimit(1)
                }
                if let departure = journey.departure {
                    Text(Format.day(departure.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Spacer(minLength: 0)
            IndicatorIcons(journey: journey)
        }
    }
}

/// A row inside a bookmark group that highlights on hover and selection.
private struct BookmarkRow<Label: View>: View {
    var isSelected: Bool
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.tint.opacity(0.22))
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.primary.opacity(0.07))
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Network

/// The network selector in the sidebar's toolbar. Ported from Railway's `ProviderPopover`.
private struct ProviderButton: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                ProviderIcon(provider: model.provider, size: 18)
                Text(model.provider.shortName)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .help("Select Network")
        .accessibilityLabel("Select Network, \(model.provider.shortName)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ProviderPicker { provider in
                model.selectProvider(provider)
                showing = false
            }
        }
    }
}

private struct ProviderPicker: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var onSelect: (Provider) -> Void

    private var groups: [(region: String, providers: [Provider])] {
        Provider.grouped.compactMap { group in
            let providers = group.providers.filter {
                query.isEmpty
                    || $0.shortName.localizedStandardContains(query)
                    || ($0.name?.localizedStandardContains(query) ?? false)
            }
            return providers.isEmpty ? nil : (group.region, providers)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Networks…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = groups.first?.providers.first { onSelect(first) }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groups, id: \.region) { group in
                        if !group.region.isEmpty {
                            Text(group.region)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                        }
                        ForEach(group.providers) { provider in
                            ProviderRow(provider: provider, isSelected: provider == model.provider) {
                                onSelect(provider)
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .frame(width: 320, height: 460)
        .onAppear { searchFocused = true }
    }
}

private struct ProviderRow: View {
    var provider: Provider
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProviderIcon(provider: provider, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.shortName).font(.body)
                    if let name = provider.name {
                        Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.08))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
