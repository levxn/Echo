import AppIntents

/// "Hey Siri, ask Echo what the plumber said." Answers from what the phone heard; nothing is shown or sent without the person's settings.
struct AskEchoIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Echo"
    static let description = IntentDescription("Ask about what Echo heard today or on another day.")
    static let openAppWhenRun = false

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    static var parameterSummary: some ParameterSummary { Summary("Ask Echo \(\.$question)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await IntentHub.shared.answer(question)
        return .result(dialog: IntentDialog(stringLiteral: reply.text))
    }
}

/// "Hey Siri, what did I promise in Echo?"
struct WhatDidIPromiseIntent: AppIntent {
    static let title: LocalizedStringResource = "What did I promise"
    static let description = IntentDescription("Reads the promises you made today.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await IntentHub.shared.promisesToday()))
    }
}

/// "Hey Siri, forget the last ten minutes in Echo."
struct ForgetLastMinutesIntent: AppIntent {
    static let title: LocalizedStringResource = "Forget the last few minutes"
    static let description = IntentDescription("Deletes what Echo heard in the last few minutes, from this phone.")
    static let openAppWhenRun = false

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 120))
    var minutes: Int

    static var parameterSummary: some ParameterSummary { Summary("Forget the last \(\.$minutes) minutes in Echo") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = IntentAnswers.clampMinutes(minutes)
        let count = await IntentHub.shared.forgetRecent(minutes: m)
        return .result(dialog: IntentDialog(stringLiteral: IntentAnswers.forgot(count: count, minutes: m)))
    }
}

struct EchoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskEchoIntent(), phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) a question"],
                    shortTitle: "Ask Echo", systemImageName: "waveform")
        AppShortcut(intent: WhatDidIPromiseIntent(), phrases: ["What did I promise in \(.applicationName)", "My promises in \(.applicationName)"],
                    shortTitle: "My promises", systemImageName: "checkmark.circle")
        AppShortcut(intent: ForgetLastMinutesIntent(), phrases: ["Forget the last few minutes in \(.applicationName)", "Forget recent moments in \(.applicationName)"],
                    shortTitle: "Forget recent", systemImageName: "clock.arrow.circlepath")
    }
}
