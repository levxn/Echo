import Foundation

/// The full answer to a past question, kept so it can be reopened without asking again. For a Muse answer this is the
/// answer after names were restored, so no placeholders are ever stored.
struct AskDetail: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case local, cloud, note }

    struct Item: Codable, Equatable, Sendable, Identifiable {
        var title: String
        var detail: String
        var when: String
        var sourceTime: String
        /// The moment on this phone the citation points at, resolved when the answer was saved (so it can still play).
        var chunkID: String?
        var id: String { "\(sourceTime)|\(title)" }
    }

    var kind: Kind
    var headline: String
    var items: [Item] = []
    /// Moments a local answer came from.
    var sourceChunkIDs: [String] = []
    var terms: [String] = []
    /// Why there is no answer, or what happened ("Cloud is off", "You chose not to send this").
    var note: String?
}

/// One question the user asked, and what it got. Stored only on this phone.
struct AskRecord: Identifiable, Equatable, Sendable {
    var id: String
    var timestamp: Date
    var question: String
    /// A sentence or two, for list rows and the watch.
    var shortAnswer: String
    var source: WatchAnswer.Source
    var via: AskVia
    var detail: AskDetail
    var milliseconds: Int

    init(id: String = UUID().uuidString, timestamp: Date = Date(), question: String, shortAnswer: String,
         source: WatchAnswer.Source, via: AskVia, detail: AskDetail, milliseconds: Int = 0) {
        self.id = id; self.timestamp = timestamp; self.question = question; self.shortAnswer = shortAnswer
        self.source = source; self.via = via; self.detail = detail; self.milliseconds = milliseconds
    }

    /// The short form that crosses to the watch.
    var item: HistoryItem {
        HistoryItem(id: id, timestamp: timestamp, question: question, answer: shortAnswer, source: source, via: via)
    }
}
