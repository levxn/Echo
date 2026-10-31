import Foundation

/// Where the Meta Model API key comes from. It lives in the app's container (written by
/// `Tools/set_api_key.sh`) or in `MODEL_API_KEY` for development, and is never in the repo,
/// build settings or logs.
enum APIKeyStore {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Echo", directoryHint: .isDirectory)
    }

    /// The placeholder shipped in `Config/meta_api_key.txt` starts with this; it must never be used as a key.
    static let placeholderPrefix = "PASTE_"

    /// Returns a usable key, or nil for blank values, the placeholder, or anything with whitespace inside.
    static func sanitized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix(placeholderPrefix),
              key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return key
    }

    static func load(directory: URL = APIKeyStore.directory, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let fromEnv = sanitized(environment["MODEL_API_KEY"]) { return fromEnv }
        return sanitized(try? String(contentsOf: directory.appending(path: "meta_api_key"), encoding: .utf8))
    }

    /// Replaces any occurrence of the key in text that might be logged or shown.
    static func redacted(_ text: String, key: String?) -> String {
        guard let key, !key.isEmpty else { return text }
        return text.replacingOccurrences(of: key, with: "•••")
    }
}

/// Chooses the live client when a key exists, otherwise the labeled stub.
enum MuseClientFactory {
    static let defaultModel = "muse-spark-1.3"
    /// Newest first. If an account can't use one, the client falls back to the next.
    static let modelChain = ["muse-spark-1.3", "muse-spark-1.2", "muse-spark-1.1"]
    private static let rememberedKey = "echo.museModel"

    static var model: String {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-muse-model"), i + 1 < args.count { return args[i + 1] }
        if let env = ProcessInfo.processInfo.environment["MUSE_MODEL"] { return env }
        return UserDefaults.standard.string(forKey: rememberedKey) ?? defaultModel
    }

    static func nextModel(after model: String) -> String? {
        guard let i = modelChain.firstIndex(of: model), i + 1 < modelChain.count else { return nil }
        return modelChain[i + 1]
    }

    /// Remembers a fallback model that worked, so later calls don't retry the one the account can't use.
    static func remember(model: String) { UserDefaults.standard.set(model, forKey: rememberedKey) }

    static func make() -> any MuseClient {
        if ProcessInfo.processInfo.arguments.contains("-stub") { return StubMuseClient() }
        if let key = APIKeyStore.load() { return MetaModelAPIClient(apiKey: key) }
        return StubMuseClient()
    }
}
