import Foundation

/// A chat request to Muse, built to the Meta Model API's documented shape.
/// Text only: there is no way to attach audio, by construction.
struct MuseRequest {
    var model: String
    /// The `developer` message (Meta prefers it over `system`): role and rules.
    var developer: String
    /// The `user` message: the question plus the transcript snippets.
    var user: String
    var schemaName: String
    /// JSON Schema (as JSON text) for `response_format`.
    var schemaJSON: String
    var maxCompletionTokens = 800
    /// `none` is rejected by Muse Spark (HTTP 400).
    var reasoningEffort = "low"

    /// True: ask for JSON-schema structured output. False: the fallback some accounts or models need, where
    /// the schema is spelled out in the instructions instead.
    var structuredOutput = true

    /// The exact bytes that go on the wire. Deliberately omits `temperature`, `stop`, `n`, `logprobs`
    /// and the other parameters the API rejects.
    func bodyData() throws -> Data {
        var rules = developer
        if !structuredOutput {
            rules += "\n\nReply with ONLY a single JSON object, with no code fences and no commentary, that conforms to this JSON Schema:\n\(schemaJSON)"
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "developer", "content": rules],
                ["role": "user", "content": user],
            ],
            "max_completion_tokens": maxCompletionTokens,
            "reasoning_effort": reasoningEffort,
        ]
        if structuredOutput {
            let schema = try JSONSerialization.jsonObject(with: Data(schemaJSON.utf8))
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "schema": schema],
            ]
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

struct MuseResponse {
    /// `choices[0].message.content`: a JSON string when structured output is requested.
    let content: String
    let model: String
    let promptTokens: Int
    let completionTokens: Int
    let latencyMs: Double
    let isStub: Bool
}

enum MuseError: Error, Equatable, LocalizedError {
    case rejected(String)       // 401 / 403
    case badRequest(String)     // 400
    case rateLimited            // 429 after one retry
    case timedOut               // 504 or client timeout
    case offline
    case server(Int, String)
    case malformed

    var errorDescription: String? {
        switch self {
        case .rejected(let m): "Meta rejected the API key\(m.isEmpty ? "" : " (\(m))"). Check it and try again."
        case .badRequest(let m): "Meta couldn't process the request: \(m)"
        case .rateLimited: "Meta's API is rate limiting requests right now. Try again in a moment."
        case .timedOut: "Muse took too long to answer."
        case .offline: "No internet connection, so Muse couldn't be reached."
        case .server(let code, let m): "Meta's API returned an error (\(code)\(m.isEmpty ? "" : ": \(m)"))."
        case .malformed: "Muse's reply couldn't be read."
        }
    }
}

protocol MuseClient {
    /// True for the offline stand-in, so the UI and ledger can label it.
    var isStub: Bool { get }
    func complete(_ request: MuseRequest) async throws -> MuseResponse
}

/// The live client: `POST https://api.meta.ai/v1/chat/completions` with a Bearer key.
struct MetaModelAPIClient: MuseClient {
    let apiKey: String
    var session: URLSession = .shared
    var endpoint = URL(string: "https://api.meta.ai/v1/chat/completions")!
    var retryDelay: Duration = .milliseconds(1500)

    var isStub: Bool { false }

    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        var current = request
        var triedPlain = false, retriedRateLimit = false
        var triedModels: Set<String> = [request.model]
        let clock = ContinuousClock()
        let started = clock.now

        while true {
            let (status, data) = try await send(current)
            let message = Self.errorMessage(in: data)
            let lower = message.lowercased()

            switch status {
            case 200..<300:
                if current.model != request.model { MuseClientFactory.remember(model: current.model) }
                return try Self.parse(data, elapsed: started.duration(to: clock.now))
            case 429:
                guard !retriedRateLimit else { throw MuseError.rateLimited }
                retriedRateLimit = true
                try await Task.sleep(for: retryDelay + .milliseconds(Int.random(in: 0...300)))
            case 504:
                throw MuseError.timedOut
            case 400 where current.structuredOutput && !triedPlain
                && ["response_format", "json_schema", "schema"].contains(where: lower.contains):
                // Structured output refused: ask for the same JSON in plain instructions instead.
                triedPlain = true
                current.structuredOutput = false
            case _ where [400, 403, 404].contains(status) && lower.contains("model")
                && MuseClientFactory.nextModel(after: current.model).map({ !triedModels.contains($0) }) == true:
                // This account can't use that model: fall back to the next older Muse Spark.
                let next = MuseClientFactory.nextModel(after: current.model)!
                triedModels.insert(next)
                current.model = next
            case 401, 403: throw MuseError.rejected(message)
            case 400: throw MuseError.badRequest(message)
            default: throw MuseError.server(status, message)
            }
        }
    }

    /// One HTTP round trip, with network failures mapped to `MuseError`.
    private func send(_ request: MuseRequest) async throws -> (Int, Data) {
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 60)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try request.bodyData()
        do {
            let (data, response) = try await session.data(for: urlRequest)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw MuseError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw MuseError.offline
            default: throw MuseError.server(error.errorCode, error.localizedDescription)
            }
        }
    }

    static func parse(_ data: Data, elapsed: Duration) throws -> MuseResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw MuseError.malformed }
        let usage = root["usage"] as? [String: Any]
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        return MuseResponse(content: content, model: root["model"] as? String ?? "muse",
                            promptTokens: usage?["prompt_tokens"] as? Int ?? 0,
                            completionTokens: usage?["completion_tokens"] as? Int ?? 0,
                            latencyMs: ms, isStub: false)
    }

    /// OpenAI-style error envelope: `{"error": {"message": "..."}}`.
    static func errorMessage(in data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let error = root["error"] as? [String: Any], let m = error["message"] as? String { return m }
        return root["message"] as? String ?? ""
    }
}
