import Foundation
import Observation

/// The state of a "From"/"To" field: free text that resolves to a place via autocompletion.
///
/// Ported from Railway's `station_entry.rs`: requests are debounced, need at least three
/// characters, and an exact name match is selected automatically.
@Observable
final class StationField {
    private static let debounce = Duration.seconds(1)
    private static let minimumQueryLength = 3

    /// The text as typed by the user.
    private(set) var text = ""
    /// The place the text resolved to, if any.
    private(set) var place: Place?
    private(set) var suggestions: [Place] = []
    /// The suggestion highlighted with the arrow keys.
    var highlighted: Int?
    /// Whether a lookup is in flight.
    private(set) var isLoading = false

    var client: RailwayClient

    private var lookup: Task<Void, Never>?

    init(client: RailwayClient) {
        self.client = client
    }

    var isSet: Bool { place != nil }

    /// Update the text as typed by the user.
    func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        textChanged()
    }

    /// Set the text programmatically (restored, swapped or from a bookmarked search) and resolve it.
    func setInput(_ input: String) {
        text = input
        place = nil
        textChanged()
    }

    func select(_ place: Place) {
        lookup?.cancel()
        isLoading = false
        self.place = place
        text = place.name
        suggestions = []
        highlighted = nil
    }

    /// Select the highlighted suggestion; returns whether one was selected.
    @discardableResult
    func selectHighlighted() -> Bool {
        guard let highlighted, suggestions.indices.contains(highlighted) else { return false }
        select(suggestions[highlighted])
        return true
    }

    /// Hide the suggestions until the text changes again.
    func dismissSuggestions() {
        suggestions = []
        highlighted = nil
    }

    func moveHighlight(by offset: Int) {
        guard !suggestions.isEmpty else { return }
        // Cycles through "nothing highlighted" like the original.
        let positions = suggestions.count + 1
        let current = (highlighted ?? -1) + 1
        let next = (current + offset + positions) % positions
        highlighted = next == 0 ? nil : next - 1
    }

    func swap(with other: StationField) {
        (text, other.text) = (other.text, text)
        (place, other.place) = (other.place, place)
        (suggestions, other.suggestions) = ([], [])
        lookup?.cancel()
        other.lookup?.cancel()
        (isLoading, other.isLoading) = (false, false)
    }

    /// The network changed; places from the old one are invalid.
    func reset(client: RailwayClient) {
        self.client = client
        place = nil
        suggestions = []
        textChanged()
    }

    private func textChanged() {
        lookup?.cancel()
        isLoading = false
        highlighted = nil
        guard text.count >= Self.minimumQueryLength else {
            place = nil
            suggestions = []
            return
        }
        if let place, place.name == text { return }
        // Try filling an exact match; if there is one, no request is needed.
        place = suggestions.first { $0.name == text }
        if place != nil {
            suggestions = []
            return
        }

        let query = text
        let client = client
        lookup = Task {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            isLoading = true
            let places = try? await client.locations(query: query)
            guard !Task.isCancelled else { return }
            isLoading = false
            guard let places else { return }
            let candidates = places.filter { $0.id != nil }
            if let exact = candidates.first(where: { $0.name == query }) {
                select(exact)
            } else {
                suggestions = candidates
            }
        }
    }
}
