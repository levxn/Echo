import Foundation

/// Splits the history into Today / Yesterday / Earlier for the "See all" list. Pure, so it can be tested with a fixed clock.
enum HistoryGrouping {
    struct Group: Equatable {
        let title: String
        let items: [AskRecord]
    }

    /// Newest first within each group; empty groups are left out.
    static func groups(_ records: [AskRecord], now: Date = Date(), calendar: Calendar = .current) -> [Group] {
        var today: [AskRecord] = [], yesterday: [AskRecord] = [], earlier: [AskRecord] = []
        for record in records.sorted(by: { $0.timestamp > $1.timestamp }) {
            if calendar.isDate(record.timestamp, inSameDayAs: now) { today.append(record) }
            else if calendar.isDate(record.timestamp, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) { yesterday.append(record) }
            else { earlier.append(record) }
        }
        return [Group(title: "Today", items: today), Group(title: "Yesterday", items: yesterday), Group(title: "Earlier", items: earlier)]
            .filter { !$0.items.isEmpty }
    }

    /// "Today 3:42 PM", "Yesterday 9:05 AM", "Oct 30, 4:10 PM": when it was asked, for the detail view.
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) { return "Yesterday \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day()) + ", " + time
    }
}
