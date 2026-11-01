import Foundation

/// The watch's copy of the last few questions, kept so Recent still works when the phone is away. The phone is the
/// source of truth: whatever it sends replaces this list, including an empty list after Forget my day.
nonisolated struct HistoryCache {
    static let key = "echo.watchHistory"
    static let limit = 8

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var items: [HistoryItem] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    /// Replaces the list with what the phone says (newest first, at most `limit`).
    func replace(with received: [HistoryItem]) {
        save(Array(received.sorted { $0.timestamp > $1.timestamp }.prefix(Self.limit)))
    }

    /// Adds an answer the watch just got, so Recent shows it straight away, even before the phone's list arrives. A
    /// repeat of the same question moves to the top rather than appearing twice.
    func insert(_ item: HistoryItem) {
        var list = items.filter { $0.id != item.id && $0.question.lowercased() != item.question.lowercased() }
        list.insert(item, at: 0)
        save(Array(list.prefix(Self.limit)))
    }

    func clear() { defaults.removeObject(forKey: Self.key) }

    private func save(_ list: [HistoryItem]) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Self.key) }
    }
}
