import Foundation
import Testing
@testable import Echo

@MainActor
struct ProfileTests {
    @Test func initialsComeFromTheFirstTwoWords() {
        #expect(ProfileLogic.initials(from: "Jordan Lee") == "JL")
        #expect(ProfileLogic.initials(from: "jordan") == "J")
        #expect(ProfileLogic.initials(from: "  ana maria  lopez ") == "AM")
        #expect(ProfileLogic.initials(from: "") == "" && ProfileLogic.initials(from: "   ") == "" && ProfileLogic.initials(from: "123 !!") == "")
        #expect(ProfileLogic.initials(from: "Émile") == "É")
    }

    @Test func theGreetingFollowsTheHourAndUsesTheFirstName() {
        #expect(ProfileLogic.greeting(hour: 8, name: "Jordan Lee") == "Good morning, Jordan")
        #expect(ProfileLogic.greeting(hour: 13, name: "Jordan") == "Good afternoon, Jordan")
        #expect(ProfileLogic.greeting(hour: 19, name: "Jordan") == "Good evening, Jordan")
        #expect(ProfileLogic.greeting(hour: 2, name: "Jordan") == "Good night, Jordan")
        #expect(ProfileLogic.greeting(hour: 19, name: "") == "Good evening", "no name yet, no comma")
        #expect(ProfileLogic.greeting(hour: 19, name: "   ") == "Good evening")
    }

    @Test func theUsersOwnNameIsRecognizedInAnyForm() {
        #expect(ProfileLogic.isSamePerson("Jordan", as: "Jordan Lee"))
        #expect(ProfileLogic.isSamePerson("jordan", as: "Jordan"))
        #expect(ProfileLogic.isSamePerson("Mr. Jordan", as: "Jordan"))
        #expect(!ProfileLogic.isSamePerson("Priya", as: "Jordan"))
        #expect(!ProfileLogic.isSamePerson("Jordan", as: ""), "no profile name, nobody is the user")
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
        #expect(a.name == "" && a.colorIndex == 0 && a.initials == "")
        a.name = "Jordan Lee"
        a.colorIndex = 3
        let b = ProfileStore(defaults: d, arguments: [])
        #expect(b.name == "Jordan Lee" && b.colorIndex == 3 && b.initials == "JL")
    }

    @Test func launchArgumentsSetTheProfileForScreenshots() {
        let s = ProfileStore(defaults: defaults(), arguments: ["-profile-name", "Jordan", "-profile-color", "2"])
        #expect(s.name == "Jordan" && s.colorIndex == 2)
        let missing = ProfileStore(defaults: defaults(), arguments: ["-profile-name"])
        #expect(missing.name == "", "a flag without a value is ignored")
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
        #expect(HeaderStatus.watch(reachable: true, listening: false).label == "Watch connected")
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
