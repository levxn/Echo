import Foundation

/// A day from a while ago that is worth a look today: "a week ago today", a month ago, a year ago.
struct Resurfaced: Identifiable, Equatable {
    let dayId: String
    /// "A week ago today"
    let title: String
    /// The most representative sentence of the day's biggest conversation, picked on the phone with no model.
    let gist: String
    let conversations: Int
    let moments: Int
    /// What to ask to see that day ("What happened a week ago?").
    let question: String
    var id: String { dayId }
}

/// Finds memories on the same date a week, a month or a year ago. Pure.
enum Resurfacing {
    static let spans: [(days: Int, title: String, phrase: String)] = [
        (7, "A week ago today", "a week ago"), (30, "A month ago today", "a month ago"), (365, "A year ago today", "a year ago"),
    ]

    static func suggestions(from chunks: [ChunkRecord], now: Date = Date(), calendar: Calendar = .current) -> [Resurfaced] {
        spans.compactMap { span in
            let day = DayID.id(offset: -span.days, from: now, calendar: calendar)
            let moments = chunks.filter { $0.dayId == day && $0.status == .stored && !($0.transcript ?? "").isEmpty }
            guard !moments.isEmpty else { return nil }
            let episodes = EpisodeBuilder.build(from: moments)
            guard let best = episodes.max(by: { $0.chunks.count < $1.chunks.count }) else { return nil }
            return Resurfaced(dayId: day, title: span.title, gist: best.gist, conversations: episodes.count, moments: moments.count,
                             question: "What happened \(span.phrase)?")
        }
    }
}
