import Foundation
import Observation
import SwiftUI

/// The profile is a name and a colour, kept only on this phone. There is no account and no login.
nonisolated enum ProfileLogic {
    static let colorCount = 6

    /// "Levin Shah" -> "LS", "levin" -> "L", "  " -> "". At most two letters.
    static func initials(from name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: \.isLetter) }
        let letters = words.prefix(2).compactMap { $0.first(where: \.isLetter) }
        return String(letters).uppercased()
    }

    /// "Good evening, Levin", or just "Good evening" before a name is set.
    static func greeting(hour: Int, name: String) -> String {
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        case 17..<22: part = "Good evening"
        default: part = "Good night"
        }
        let first = name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return first.isEmpty ? part : "\(part), \(first)"
    }

    /// True when `name` is the profile's name (first name, any case): used to avoid labelling the user's own
    /// commitments as being made "to" themselves.
    static func isSamePerson(_ candidate: String, as profileName: String) -> Bool {
        guard let mine = profileName.split(whereSeparator: { $0.isWhitespace }).first?.lowercased(), !mine.isEmpty else { return false }
        return candidate.split(whereSeparator: { $0.isWhitespace }).contains { $0.lowercased() == mine }
    }
}

@MainActor
@Observable
final class ProfileStore {
    static let nameKey = "echo.profileName"
    static let colorKey = "echo.profileColor"
    static let speakKey = "echo.speakVoiceAnswers"
    static let catchKey = "echo.catchPromises"
    /// Whose day this is until they type their own name.
    static let defaultName = "Levin"

    private let defaults: UserDefaults

    var name: String {
        didSet { defaults.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.nameKey) }
    }
    var colorIndex: Int {
        didSet { defaults.set(colorIndex, forKey: Self.colorKey) }
    }
    /// When you say you will do something, the watch shows "Got it" and offers a reminder. On unless turned off.
    var catchPromises: Bool {
        didSet { defaults.set(catchPromises, forKey: Self.catchKey) }
    }
    /// A nudge at 9 pm to write the day's journal entry. Off unless turned on.
    var journalReminder: Bool {
        didSet { defaults.set(journalReminder, forKey: JournalReminder.key) }
    }
    /// Read answers aloud when the question was spoken. On unless turned off.
    var speakVoiceAnswers: Bool {
        didSet { defaults.set(speakVoiceAnswers, forKey: Self.speakKey) }
    }

    /// Dev hooks for screenshots and the demo take: `-profile-name Levin`, `-profile-color 2`.
    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        func value(_ flag: String) -> String? { arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } }
        if let n = value("-profile-name") { defaults.set(n, forKey: Self.nameKey) }
        if let c = value("-profile-color").flatMap(Int.init) { defaults.set(c, forKey: Self.colorKey) }
        name = defaults.string(forKey: Self.nameKey) ?? Self.defaultName
        let stored = defaults.object(forKey: Self.colorKey) as? Int ?? 0
        colorIndex = ((stored % ProfileLogic.colorCount) + ProfileLogic.colorCount) % ProfileLogic.colorCount
        speakVoiceAnswers = defaults.object(forKey: Self.speakKey) as? Bool ?? true
        catchPromises = defaults.object(forKey: Self.catchKey) as? Bool ?? true
        journalReminder = defaults.bool(forKey: JournalReminder.key)
    }

    var initials: String { ProfileLogic.initials(from: name) }
    var greeting: String { ProfileLogic.greeting(hour: Calendar.current.component(.hour, from: Date()), name: name) }
    var color: Color { Self.palette[colorIndex] }

    static let palette: [Color] = [
        Palette.teal, Palette.blue, Palette.violet, Palette.rose, Palette.amber, Color(red: 0.42, green: 0.84, blue: 0.47),
    ]
}
