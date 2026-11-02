import Foundation

/// A JSON copy of the privacy ledger that the user can keep or share: what was asked, where it was answered,
/// and the exact text that was sent. Replies from Muse (which describe the user's day) and audio are not included.
struct LedgerExport: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let id: String
        let timestamp: Date
        let kind: String
        let query: String
        let tier: String
        let reason: String
        let leftDevice: Bool
        let model: String
        let isStub: Bool
        let bodyBytes: Int
        let status: String
        let error: String
        let promptTokens: Int
        let completionTokens: Int
        let latencyMs: Double
        /// People's names replaced with placeholders before sending; `snippets` is the masked text that left.
        let maskedNames: Int
        /// Exactly the text that was (or, when `leftDevice` is false, would have been) sent.
        let snippets: [Snippet]
    }

    let app: String
    let exportedAt: Date
    let note: String
    let entries: [Entry]

    init(entries: [LedgerEntry], now: Date = Date()) {
        app = "Echo"
        exportedAt = now
        note = "Each entry lists the exact text sent to the cloud. Audio is never sent, and Muse's replies are not included here."
        self.entries = entries.map {
            Entry(id: $0.id, timestamp: $0.timestamp, kind: $0.kind.rawValue, query: $0.query, tier: $0.tier.rawValue,
                  reason: $0.reason, leftDevice: $0.leftDevice, model: $0.model, isStub: $0.isStub, bodyBytes: $0.bodyBytes,
                  status: $0.status.rawValue, error: $0.error, promptTokens: $0.promptTokens,
                  completionTokens: $0.completionTokens, latencyMs: $0.latencyMs, maskedNames: $0.maskedNames, snippets: $0.snippets)
        }
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Writes `echo-ledger-YYYY-MM-DD.json` into `directory` and returns its URL.
    func write(into directory: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let url = directory.appending(path: "echo-ledger-\(formatter.string(from: exportedAt)).json")
        try jsonData().write(to: url, options: .atomic)
        return url
    }
}

/// "Forget my day": removes everything Echo kept about the day, on this phone, while the app is running.
/// The API key, the cloud switch and other settings stay, and so does the ledger unless asked otherwise
/// (it is the record of what already left the phone).
@MainActor
enum DayWiper {
    static let promiseDoneKey = "echo.promiseDone"

    static func forget(resetDay: () async -> Void, ask: AskModel, digest: DigestModel, player: ChunkPlayer,
                       ledger: LedgerModel, includeLedger: Bool, reminders: Reminders? = nil, voices: VoiceBookModel? = nil,
                       defaults: UserDefaults = .standard) async {
        player.stop()
        ask.clear()
        digest.reset()
        await resetDay()   // transcripts, search index, audio files, the saved digest, the ask history, and the replay session
        await ask.history?.clear()
        reminders?.clearAll()
        voices?.clear()
        defaults.removeObject(forKey: promiseDoneKey)
        defaults.removeObject(forKey: PeopleIgnore.key)
        if includeLedger { await ledger.clear() } else { await ledger.redactResponses() }
    }
}
