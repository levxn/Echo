import Foundation

/// Wipes the day's data so a demo can be re-recorded from a clean slate, without uninstalling the app
/// (uninstalling would reset the speech-recognition permission). Keeps the API key.
///
/// Triggered by the dev launch argument `-reset-demo <token>`, once per token: the system can relaunch an app
/// with the same arguments, and that must never wipe a demo in progress.
enum DemoReset {
    static let tokenKey = "echo.resetDemoToken"
    private static let preserved: Set<String> = ["meta_api_key"]

    /// The `-reset-demo` token from the launch arguments, if any.
    static func requestedToken(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let i = arguments.firstIndex(of: "-reset-demo"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// Runs the wipe if `token` hasn't been used before. Returns whether it ran.
    @discardableResult
    static func runIfNeeded(token: String?, directory: URL = APIKeyStore.directory, defaults: UserDefaults = .standard) -> Bool {
        guard let token, defaults.string(forKey: tokenKey) != token else { return false }
        wipe(directory: directory, defaults: defaults)
        defaults.set(token, forKey: tokenKey)
        return true
    }

    /// Deletes the database, chunk audio and session state; leaves the API key in place.
    static func wipe(directory: URL, defaults: UserDefaults) {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where !preserved.contains(item.lastPathComponent) {
            try? fm.removeItem(at: item)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("echo.") && key != tokenKey {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: "echo.cloudEnabled")   // the demo starts with the cloud switch on
    }
}
