import Foundation
import Testing
@testable import Echo

struct WelcomeTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "echo-welcome-\(UUID().uuidString)")! }

    @Test func aFirstPlainLaunchShowsTheWelcomeOnce() {
        let d = defaults()
        #expect(Welcome.isPending(arguments: ["Echo"], defaults: d))
        Welcome.markSeen(defaults: d)
        #expect(!Welcome.isPending(arguments: ["Echo"], defaults: d))
    }

    @Test func theSystemsOwnFlagsDoNotCountAsDeveloperFlags() {
        #expect(!Welcome.hasDeveloperFlags(["Echo", "-NSDocumentRevisionsDebugMode", "YES", "-AppleLanguages", "(en)"]))
        #expect(Welcome.hasDeveloperFlags(["Echo", "-tab", "ask"]))
        #expect(Welcome.hasDeveloperFlags(["Echo", "-demo-script", "full"]))
    }

    @Test func aDeveloperLaunchSkipsTheWelcomeAndCountsAsHavingSeenIt() {
        let d = defaults()
        #expect(!Welcome.isPending(arguments: ["Echo", "-tab", "today"], defaults: d))
        #expect(!Welcome.isPending(arguments: ["Echo"], defaults: d), "the next plain launch of that install isn't interrupted either")
    }

    @Test func showWelcomeBringsItBack() {
        let d = defaults()
        Welcome.markSeen(defaults: d)
        #expect(Welcome.isPending(arguments: ["Echo", "-show-welcome"], defaults: d))
    }

    @Test func theLaunchMarkPlaysOnlyOnAnOrdinaryLaunchAfterTheWelcome() {
        let d = defaults()
        #expect(!Welcome.showsLaunchMark(arguments: ["Echo"], defaults: d), "the welcome is showing instead")
        Welcome.markSeen(defaults: d)
        #expect(Welcome.showsLaunchMark(arguments: ["Echo"], defaults: d))
        #expect(!Welcome.showsLaunchMark(arguments: ["Echo", "-tab", "ask"], defaults: d))
    }
}
