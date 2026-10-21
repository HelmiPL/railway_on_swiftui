import SwiftUI

/// The search options as one value, so they can be edited as a draft and applied together.
struct SearchOptions: Equatable {
    var loyaltyCard: Int
    var firstClass: Bool
    var bikeAccessible: Bool
    var transferTime: Int
    var directOnly: Bool
    var modes: Set<TransportMode>

    static func load(from defaults: UserDefaults = .standard) -> SearchOptions {
        SearchOptions(
            loyaltyCard: defaults.integer(forKey: SettingsKey.loyaltyCard),
            firstClass: defaults.bool(forKey: SettingsKey.firstClass),
            bikeAccessible: defaults.bool(forKey: SettingsKey.bikeAccessible),
            transferTime: defaults.integer(forKey: SettingsKey.transferTime),
            directOnly: defaults.bool(forKey: SettingsKey.directOnly),
            modes: Set(TransportMode.allCases.filter { defaults.bool(forKey: SettingsKey.include($0)) })
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(loyaltyCard, forKey: SettingsKey.loyaltyCard)
        defaults.set(firstClass, forKey: SettingsKey.firstClass)
        defaults.set(bikeAccessible, forKey: SettingsKey.bikeAccessible)
        defaults.set(transferTime, forKey: SettingsKey.transferTime)
        defaults.set(directOnly, forKey: SettingsKey.directOnly)
        for mode in TransportMode.allCases {
            defaults.set(modes.contains(mode), forKey: SettingsKey.include(mode))
        }
    }
}

extension SearchOptions {
    /// What a new installation searches with.
    static let defaults = SearchOptions(
        loyaltyCard: LoyaltyCard.none.rawValue,
        firstClass: false,
        bikeAccessible: false,
        transferTime: 0,
        directOnly: false,
        modes: Set(TransportMode.allCases)
    )

    var isCustomized: Bool { self != .defaults }
}

/// The toolbar button opening the search options.
enum SearchOptionsButton {
    static var title: String { String(localized: "Search Options") }

    static var help: String {
        let summary = UserDefaults.standard.searchOptionsSummary
        return String(localized: "Refine Advanced Search Options") + (SearchOptions.load().isCustomized ? " (\(summary))" : "")
    }
}

/// Search options, ported from Railway's `SearchOptionsDialog`.
struct SearchOptionsForm: View {
    @Binding var options: SearchOptions

    var body: some View {
        Form {
            Section {
                Picker("Discount Card", selection: $options.loyaltyCard) {
                    ForEach(LoyaltyCard.allCases) { card in
                        Text(card.title).tag(card.rawValue)
                    }
                }
                LabeledContent("Class") {
                    NativeSegmentedControl(selection: $options.firstClass, options: [
                        (true, String(localized: "First Class")),
                        (false, String(localized: "Second Class")),
                    ], shape: .roundedRectangle)
                    .frame(width: 240)
                    .accessibilityLabel("Class")
                }
                Toggle("Bike Accessible", isOn: $options.bikeAccessible)
                LabeledContent("Minimum Transfer Time") {
                    ValueStepper(value: $options.transferTime, range: 0...60, step: 5) { "\($0) min" }
                }
                Toggle("Direct Connections Only", isOn: $options.directOnly)
            }

            Section("Modes of Transport") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(TransportMode.allCases) { mode in
                        Toggle(isOn: Binding(
                            get: { options.modes.contains(mode) },
                            set: { included in
                                if included { options.modes.insert(mode) } else { options.modes.remove(mode) }
                            }
                        )) {
                            Label(mode.title, systemImage: mode.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.button)
                        .buttonBorderShape(.roundedRectangle(radius: 6))
                        .controlSize(.large)
                    }
                }
                // The same 8 pt on every side as between the buttons; their corners nest inside
                // the box's.
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
        .formStyle(.grouped)
    }
}

/// The sheet opened from "More Options": changes only take effect when applied.
struct SearchOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var original = SearchOptions.load()
    @State private var draft = SearchOptions.load()

    var body: some View {
        VStack(spacing: 0) {
            // A plain header, aligned with the form's content (a navigation title would be centred).
            Text("Search Options")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 2)

            SearchOptionsForm(options: $draft)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    draft.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(draft == original)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 580)
    }
}

/// In the Settings window, search options apply immediately, as usual for Mac settings.
private struct LiveSearchOptionsForm: View {
    @State private var options = SearchOptions.load()

    var body: some View {
        SearchOptionsForm(options: $options)
            .onChange(of: options) { _, new in new.save() }
            // Pick up changes applied from the sheet while the Settings window is open.
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                let stored = SearchOptions.load()
                if stored != options { options = stored }
            }
    }
}

/// The Settings window, ported from Railway's `PreferencesDialog`; also hosts the search options.
struct SettingsView: View {
    var body: some View {
        TabView {
            // macOS only draws the bar behind the tabs while hovering; draw it permanently.
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
                    .toolbarBand(.raised)
            }
            Tab("Search", systemImage: "magnifyingglass") {
                LiveSearchOptionsForm()
                    .toolbarBand(.raised)
            }
        }
        .frame(width: 520)
        .frame(minHeight: 300)
        .background(FixedWindowTitle(title: String(localized: "Railway Settings")))
    }
}

/// Keeps a window's title fixed. Settings windows otherwise show the selected tab's name, which
/// SwiftUI sets again on every tab switch.
private struct FixedWindowTitle: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> TitleView {
        TitleView(title: title)
    }

    func updateNSView(_ view: TitleView, context: Context) {
        view.title = title
        view.apply()
    }

    final class TitleView: NSView {
        var title: String
        private var observation: NSKeyValueObservation?

        init(title: String) {
            self.title = title
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.title) { [weak self] _, _ in
                DispatchQueue.main.async { self?.apply() }
            }
            apply()
        }

        func apply() {
            guard let window, window.title != title else { return }
            window.title = title
        }
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.deleteOld) private var deleteOld = false
    @AppStorage(SettingsKey.deletionTime) private var deletionTime = 2
    @AppStorage(SettingsKey.animateBackground) private var animateBackground = true

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle(isOn: $animateBackground) {
                    Text("Animate Trip Background")
                    Text("Slowly moves the colours behind the trip details")
                }
            }
            Section("Bookmarks") {
                Toggle(isOn: $deleteOld) {
                    Text("Automatically Remove Old Bookmarks")
                    Text("Past trips are kept only for a period of time")
                }
                LabeledContent {
                    ValueStepper(value: $deletionTime, range: 0...48, step: 1) { "\($0) h" }
                } label: {
                    Text("Preservation Time For Trips")
                    Text("For how long to retain trips after arrival")
                }
                .disabled(!deleteOld)
            }
        }
        .formStyle(.grouped)
    }
}

/// A number with a stepper next to it, like libadwaita's `SpinRow`.
private struct ValueStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var format: (Int) -> LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Text(format(value))
                .monospacedDigit()
            Stepper(value: $value, in: range, step: step) {
                Text(format(value))
            }
            .labelsHidden()
        }
    }
}
