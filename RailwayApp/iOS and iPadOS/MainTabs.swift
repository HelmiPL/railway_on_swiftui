import SwiftUI

/// The iOS/iPadOS app: search, bookmarks and settings as tabs. Trips open in a sheet over all of them.
struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack {
                    SearchView()
                }
            }
            Tab("Bookmarks", systemImage: "bookmark", value: .bookmarks) {
                NavigationStack {
                    BookmarksScreen()
                }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .feedback(for: model)
    }
}

/// The trip details (the Mac's third column) in a sheet.
struct TripSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            JourneyDetailView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}

/// The settings in a sheet, opened from the sidebar on iPad.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}

/// Bookmarked trips and searches.
private struct BookmarksScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.journeyStore.journeys.isEmpty, model.searchStore.searches.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Bookmark a trip or a search to find it here.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        BookmarkLists()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle("Bookmarks")
    }
}
