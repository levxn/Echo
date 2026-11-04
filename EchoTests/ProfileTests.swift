import Foundation
import Testing
@testable import Echo

@MainActor
struct ProfileTests {
    @Test func initialsComeFromTheFirstTwoWords() {
        #expect(ProfileLogic.initials(from: "Levin Shah") == "LS")
        #expect(ProfileLogic.initials(from: "levin") == "L")
        #expect(ProfileLogic.initials(from: "  ana maria  lopez ") == "AM")
        #expect(ProfileLogic.initials(from: "") == "" && ProfileLogic.initials(from: "   ") == "" && ProfileLogic.initials(from: "123 !!") == "")
        #expect(ProfileLogic.initials(from: "Émile") == "É")
    }

    @Test func theGreetingFollowsTheHourAndUsesTheFirstName() {
        #expect(ProfileLogic.greeting(hour: 8, name: "Levin Shah") == "Good morning, Levin")
        #expect(ProfileLogic.greeting(hour: 13, name: "Levin") == "Good afternoon, Levin")
        #expect(ProfileLogic.greeting(hour: 19, name: "Levin") == "Good evening, Levin")
        #expect(ProfileLogic.greeting(hour: 2, name: "Levin") == "Good night, Levin")
        #expect(ProfileLogic.greeting(hour: 19, name: "") == "Good evening", "no name yet, no comma")
        #expect(ProfileLogic.greeting(hour: 19, name: "   ") == "Good evening")
    }

    @Test func theUsersOwnNameIsRecognizedInAnyForm() {
        #expect(ProfileLogic.isSamePerson("Levin", as: "Levin Shah"))
        #expect(ProfileLogic.isSamePerson("levin", as: "Levin"))
        #expect(ProfileLogic.isSamePerson("Mr. Levin", as: "Levin"))
        #expect(!ProfileLogic.isSamePerson("Priya", as: "Levin"))
        #expect(!ProfileLogic.isSamePerson("Levin", as: ""), "no profile name, nobody is the user")
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "echo-profile-\(UUID().uuidString)")! }

    @Test func spokenAnswersAreOnByDefaultAndTheChoiceIsRemembered() {
        let d = defaults()
        let first = ProfileStore(defaults: d, arguments: [])
        #expect(first.speakVoiceAnswers, "on until turned off")
        first.speakVoiceAnswers = false
        #expect(!ProfileStore(defaults: d, arguments: []).speakVoiceAnswers)
        first.speakVoiceAnswers = true
        #expect(ProfileStore(defaults: d, arguments: []).speakVoiceAnswers)
    }

    @Test func theProfileIsSavedAndReloaded() {
        let d = defaults()
        let a = ProfileStore(defaults: d, arguments: [])
        #expect(a.name == ProfileStore.defaultName && a.colorIndex == 0 && a.initials == "L", "Levin until they type their own name")
        a.name = "Levin Shah"
        a.colorIndex = 3
        let b = ProfileStore(defaults: d, arguments: [])
        #expect(b.name == "Levin Shah" && b.colorIndex == 3 && b.initials == "LS")
    }

    @Test func launchArgumentsSetTheProfileForScreenshots() {
        let s = ProfileStore(defaults: defaults(), arguments: ["-profile-name", "Levin", "-profile-color", "2"])
        #expect(s.name == "Levin" && s.colorIndex == 2)
        let missing = ProfileStore(defaults: defaults(), arguments: ["-profile-name"])
        #expect(missing.name == ProfileStore.defaultName, "a flag without a value is ignored")
    }

    @Test func aStoredColourOutOfRangeIsFoldedBackIn() {
        let d = defaults()
        d.set(ProfileLogic.colorCount + 2, forKey: ProfileStore.colorKey)
        #expect(ProfileStore(defaults: d, arguments: []).colorIndex == 2)
        d.set(-1, forKey: ProfileStore.colorKey)
        #expect((0..<ProfileLogic.colorCount).contains(ProfileStore(defaults: d, arguments: []).colorIndex))
        #expect(ProfileStore.palette.count == ProfileLogic.colorCount)
    }

    // MARK: Header indicators

    @Test func theWatchIndicatorSaysWhetherItIsThereAndListening() {
        #expect(HeaderStatus.watch(reachable: false, listening: false) == .init(symbol: "applewatch.slash", label: "Watch not reachable", tint: .amber))
        #expect(HeaderStatus.watch(reachable: true, listening: false) == .init(symbol: "waveform", label: "Watch connected, not listening", tint: .teal),
                "the same bars as while listening, which TopBar only animates when listening")
        #expect(HeaderStatus.watch(reachable: true, listening: true).symbol == "waveform", "listening wins over connected")
        #expect(HeaderStatus.watch(reachable: false, listening: true).tint == .teal)
    }

    @Test func theCloudIndicatorShowsOnOffAndReview() {
        #expect(HeaderStatus.cloud(enabled: true, reviewing: false) == .init(symbol: "cloud.fill", label: "Cloud is on for broad questions", tint: .violet))
        #expect(HeaderStatus.cloud(enabled: true, reviewing: true).label.contains("approve"))
        let off = HeaderStatus.cloud(enabled: false, reviewing: true)
        #expect(off.symbol == "cloud.slash" && off.tint == .amber && off.label.contains("Nothing is sent"), "off wins over review")
    }

    @Test func everyIndicatorHasALabelForVoiceOver() {
        let all = [HeaderStatus.watch(reachable: true, listening: false), HeaderStatus.watch(reachable: false, listening: false),
                   HeaderStatus.cloud(enabled: true, reviewing: false), HeaderStatus.cloud(enabled: false, reviewing: false), HeaderStatus.lock]
        #expect(all.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
    }
}
