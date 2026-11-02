import Foundation
import Observation

/// The phone's knowledge of who is talking: the voices it has learned to tell apart, which one is "me", and the names the
/// person has given. Everything stays on this phone and is cleared by Forget my day.
@MainActor
@Observable
final class VoiceBookModel {
    private(set) var book = SpeakerBook()
    private let store: ChunkStore

    init(store: ChunkStore) { self.store = store }

    var voices: [Voice] { book.speakers.sorted { $0.count > $1.count } }
    var me: Voice? { book.me }
    func voice(id: String) -> Voice? { id.isEmpty ? nil : book.speakers.first { $0.id == id } }

    func load() async { book.speakers = await store.speakers() }

    /// With nobody marked as "me" yet, the voice heard most is very likely the person wearing the watch: it is closest to the
    /// microphone and talks all day. Offered, never assumed.
    var suggestedMe: Voice? {
        guard me == nil, let top = voices.first else { return nil }
        let total = book.speakers.reduce(0) { $0 + $1.count }
        return total >= 6 && Float(top.count) / Float(total) >= 0.3 ? top : nil
    }

    /// Says whose voice a moment is, and remembers it. Returns the voice's id (nil if there wasn't enough speech to tell).
    func identify(chunkID: String, print: VoicePrint?) async -> String? {
        guard let print else { return nil }
        let voice = book.assign(print)
        await store.saveSpeaker(voice)
        await store.setVoice(chunkID: chunkID, speakerID: voice.id, print: print.data)
        return voice.id
    }

    func rename(_ id: String, to name: String) async {
        guard let i = book.speakers.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        book.speakers[i].name = trimmed.isEmpty ? nil : trimmed
        await store.saveSpeaker(book.speakers[i])
    }

    /// "This is me": the one voice that is the person wearing the watch.
    func setMe(_ id: String?) async {
        book.setMe(id)
        for v in book.speakers { await store.saveSpeaker(v) }
    }

    func merge(_ other: String, into keep: String) async {
        guard book.speakers.contains(where: { $0.id == other }), book.speakers.contains(where: { $0.id == keep }) else { return }
        book.merge(other, into: keep)
        await store.reassignVoice(from: other, to: keep)
        await store.deleteSpeakerRow(id: other)
        if let kept = voice(id: keep) { await store.saveSpeaker(kept) }
    }

    /// Forgets one voice: its moments are no longer attributed to anyone.
    func forget(_ id: String) async {
        book.speakers.removeAll { $0.id == id }
        await store.deleteSpeaker(id: id)
    }

    /// Everything, when the day is forgotten.
    func clear() { book = SpeakerBook() }
}
