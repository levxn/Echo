import Foundation

/// When to show the welcome screen and the launch mark. Both are for a person opening Echo, so any launch that carries a
/// developer flag (`-tab`, `-ask`, `-demo-script` ...) skips them, and `-show-welcome` brings the welcome back.
nonisolated enum Welcome {
    static let key = "echo.welcomed"

    /// Flags the system adds itself ("-NSDocumentRevisionsDebugMode", "-AppleLanguages") don't count.
    static func hasDeveloperFlags(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains { $0.hasPrefix("-") && !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") && !$0.hasPrefix("-com.apple") && $0 != "-show-welcome" && $0 != "-welcome-page" }
    }

    static func isPending(arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard) -> Bool {
        if arguments.contains("-show-welcome") { return true }
        // A developer launch counts as having been through it, so later plain launches of the same install aren't interrupted.
        if hasDeveloperFlags(arguments) { defaults.set(true, forKey: key); return false }
        return !defaults.bool(forKey: key)
    }

    static func markSeen(defaults: UserDefaults = .standard) { defaults.set(true, forKey: key) }

    /// The launch mark plays on an ordinary launch that isn't the welcome.
    static func showsLaunchMark(arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard) -> Bool {
        !hasDeveloperFlags(arguments) && !isPending(arguments: arguments, defaults: defaults)
    }
}
