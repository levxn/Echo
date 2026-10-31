import Foundation

/// Where the Meta Model API key comes from. It lives in the app's container (written by
/// `Tools/set_api_key.sh`) or in `MODEL_API_KEY` for development, and is never in the repo,
/// build settings or logs.
enum APIKeyStore {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Echo", directoryHint: .isDirectory)
    }

    static func load(directory: URL = APIKeyStore.directory, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let fromEnv = environment["MODEL_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !fromEnv.isEmpty {
            return fromEnv
        }
        let file = directory.appending(path: "meta_api_key")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
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

    static var model: String {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-muse-model"), i + 1 < args.count { return args[i + 1] }
        return ProcessInfo.processInfo.environment["MUSE_MODEL"] ?? defaultModel
    }

    static func make() -> any MuseClient {
        if ProcessInfo.processInfo.arguments.contains("-stub") { return StubMuseClient() }
        if let key = APIKeyStore.load() { return MetaModelAPIClient(apiKey: key) }
        return StubMuseClient()
    }
}
