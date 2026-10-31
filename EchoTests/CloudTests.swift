import Foundation
import Testing
@testable import Echo

/// Intercepts URLSession so client tests never touch the network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            Self.bodies.append(data)
        }
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() { handler = nil; requests = []; bodies = [] }

    static func respond(_ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: URL(string: "https://api.meta.ai/v1/chat/completions")!, statusCode: status,
                         httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }
}

private func makeClient(key: String = "test-key-123") -> MetaModelAPIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return MetaModelAPIClient(apiKey: key, session: URLSession(configuration: config), retryDelay: .milliseconds(1))
}

private func sampleRequest() -> MuseRequest {
    MuseRequest(model: "muse-spark-1.3", developer: "Rules.", user: "Question: what did I promise?\n09:05 — I will send it.",
                schemaName: EchoSchemas.answerName, schemaJSON: EchoSchemas.answer)
}

/// The sample response from Meta's chat-completions documentation, with structured content.
private let documentedResponse = """
{"id":"chatcmpl-abc123","object":"chat.completion","created":1714502400,"model":"muse-spark-1.3",
 "choices":[{"index":0,"message":{"role":"assistant","content":"{\\"answer\\":\\"You promised the API spec.\\",\\"items\\":[{\\"title\\":\\"Send API spec\\",\\"detail\\":\\"To Ravi\\",\\"when\\":\\"Wednesday noon\\",\\"source_time\\":\\"09:05\\"}]}"},"finish_reason":"stop"}],
 "usage":{"prompt_tokens":25,"completion_tokens":19,"total_tokens":44}}
"""

@Suite(.serialized)
struct MuseClientTests {
    @Test func requestBodyFollowsTheDocumentedShape() throws {
        let body = try JSONSerialization.jsonObject(with: sampleRequest().bodyData()) as! [String: Any]
        #expect(body["model"] as? String == "muse-spark-1.3")
        let messages = body["messages"] as! [[String: String]]
        #expect(messages.map { $0["role"] } == ["developer", "user"], "Meta prefers developer over system")
        #expect(body["max_completion_tokens"] as? Int == 800)
        #expect(body["reasoning_effort"] as? String == "low", "'none' is rejected by Muse Spark")

        let format = body["response_format"] as! [String: Any]
        #expect(format["type"] as? String == "json_schema")
        let jsonSchema = format["json_schema"] as! [String: Any]
        #expect(jsonSchema["name"] as? String == EchoSchemas.answerName)
        #expect((jsonSchema["schema"] as? [String: Any])?["type"] as? String == "object")

        // Parameters the API answers with HTTP 400, plus anything audio-related.
        for forbidden in ["stop", "n", "logprobs", "top_logprobs", "logit_bias", "temperature", "top_p", "max_output_tokens",
                          "audio", "modalities", "prediction", "web_search_options", "max_tokens"] {
            #expect(body[forbidden] == nil, "\(forbidden) must not be sent")
        }
    }

    @Test func successfulCallParsesContentAndUsage() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in MockURLProtocol.respond(200, documentedResponse) }
        let response = try await makeClient().complete(sampleRequest())

        #expect(response.model == "muse-spark-1.3")
        #expect(response.promptTokens == 25 && response.completionTokens == 19)
        #expect(!response.isStub)
        let answer = CloudAnswer.parse(response.content)
        #expect(answer.answer == "You promised the API spec.")
        #expect(answer.items.first?.sourceTime == "09:05")

        let request = try #require(MockURLProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://api.meta.ai/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func httpErrorsMapToClearMuseErrors() async {
        func status(_ code: Int, _ body: String = "") async -> MuseError? {
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _ in MockURLProtocol.respond(code, body) }
            do { _ = try await makeClient().complete(sampleRequest()); return nil } catch { return error as? MuseError }
        }
        #expect(await status(401, #"{"error":{"message":"bad key"}}"#) == .rejected("bad key"))
        #expect(await status(403) == .rejected(""))
        #expect(await status(400, #"{"error":{"message":"reasoning_effort none is not supported"}}"#)
                == .badRequest("reasoning_effort none is not supported"))
        #expect(await status(504) == .timedOut)
        #expect(await status(500, #"{"error":{"message":"oops"}}"#) == .server(500, "oops"))
        #expect(await status(200, "not json") == .malformed)
    }

    @Test func rateLimitRetriesOnceThenSucceedsOrGivesUp() async throws {
        MockURLProtocol.reset()
        var calls = 0
        MockURLProtocol.handler = { _ in calls += 1; return calls == 1 ? MockURLProtocol.respond(429, "") : MockURLProtocol.respond(200, documentedResponse) }
        _ = try await makeClient().complete(sampleRequest())
        #expect(calls == 2)

        MockURLProtocol.reset()
        calls = 0
        MockURLProtocol.handler = { _ in calls += 1; return MockURLProtocol.respond(429, "") }
        do { _ = try await makeClient().complete(sampleRequest()); Issue.record("expected rateLimited") }
        catch { #expect(error as? MuseError == .rateLimited) }
        #expect(calls == 2, "exactly one retry")
    }

    @Test func refusedStructuredOutputIsRetriedAsPlainJSONInstructions() async throws {
        MockURLProtocol.reset()
        var calls = 0
        MockURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? MockURLProtocol.respond(400, #"{"error":{"message":"response_format json_schema is not supported with reasoning"}}"#)
                              : MockURLProtocol.respond(200, documentedResponse)
        }
        let response = try await makeClient().complete(sampleRequest())
        #expect(calls == 2 && CloudAnswer.parse(response.content).answer == "You promised the API spec.")

        let first = try JSONSerialization.jsonObject(with: try #require(MockURLProtocol.bodies.first)) as! [String: Any]
        let second = try JSONSerialization.jsonObject(with: try #require(MockURLProtocol.bodies.last)) as! [String: Any]
        #expect(first["response_format"] != nil)
        #expect(second["response_format"] == nil, "the retry drops the structured-output parameter")
        let rules = ((second["messages"] as! [[String: String]]).first?["content"]) ?? ""
        #expect(rules.contains("JSON Schema") && rules.contains("source_time"), "the schema moves into the instructions")
    }

    @Test func aRepeatedSchemaRefusalIsReportedNotLooped() async {
        MockURLProtocol.reset()
        var calls = 0
        MockURLProtocol.handler = { _ in calls += 1; return MockURLProtocol.respond(400, #"{"error":{"message":"invalid schema"}}"#) }
        do { _ = try await makeClient().complete(sampleRequest()); Issue.record("expected a failure") }
        catch { #expect(error as? MuseError == .badRequest("invalid schema")) }
        #expect(calls == 2, "one structured attempt and one plain retry, then stop")
    }

    @Test func anUnavailableModelFallsBackToTheNextOlderOne() async throws {
        let key = "echo.museModel"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { saved == nil ? UserDefaults.standard.removeObject(forKey: key) : UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)

        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in
            // URLSession delivers the body as a stream; the mock has already captured it.
            let body = String(decoding: MockURLProtocol.bodies.last ?? Data(), as: UTF8.self)
            return body.contains("muse-spark-1.3") ? MockURLProtocol.respond(404, #"{"error":{"message":"The model muse-spark-1.3 does not exist or you do not have access"}}"#)
                                                   : MockURLProtocol.respond(200, documentedResponse)
        }
        _ = try await makeClient().complete(sampleRequest())
        let models = MockURLProtocol.bodies.compactMap { body -> String? in
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["model"] as? String
        }
        #expect(models == ["muse-spark-1.3", "muse-spark-1.2"], "\(models)")
        #expect(UserDefaults.standard.string(forKey: key) == "muse-spark-1.2", "the working model is remembered")
    }

    @Test func aForbiddenResponseThatNamesTheModelAlsoFallsBack() async throws {
        let key = "echo.museModel"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { saved == nil ? UserDefaults.standard.removeObject(forKey: key) : UserDefaults.standard.set(saved, forKey: key) }
        MockURLProtocol.reset()
        var calls = 0
        MockURLProtocol.handler = { _ in
            calls += 1
            return calls == 1 ? MockURLProtocol.respond(403, #"{"error":{"message":"your account has no access to this model"}}"#)
                              : MockURLProtocol.respond(200, documentedResponse)
        }
        _ = try await makeClient().complete(sampleRequest())
        #expect(calls == 2)
    }

    @Test func fallingThroughEveryModelEndsInAnErrorAfterThreeTries() async {
        MockURLProtocol.reset()
        var calls = 0
        MockURLProtocol.handler = { _ in calls += 1; return MockURLProtocol.respond(404, #"{"error":{"message":"model not found"}}"#) }
        do { _ = try await makeClient().complete(sampleRequest()); Issue.record("expected a failure") }
        catch { #expect(error as? MuseError == .server(404, "model not found")) }
        #expect(calls == 3, "1.3, 1.2 and 1.1, then stop")
    }

    @Test func aRejectedKeyIsNotMistakenForAModelProblem() async {
        MockURLProtocol.reset()
        var calls = 0
        MockURLProtocol.handler = { _ in calls += 1; return MockURLProtocol.respond(403, #"{"error":{"message":"invalid api key"}}"#) }
        do { _ = try await makeClient().complete(sampleRequest()); Issue.record("expected a failure") }
        catch { #expect(error as? MuseError == .rejected("invalid api key")) }
        #expect(calls == 1, "no fallback for a bad key")
    }

    @Test func networkFailuresMapToOfflineAndTimeout() async {
        func fail(_ code: URLError.Code) async -> MuseError? {
            MockURLProtocol.reset()
            MockURLProtocol.handler = { _ in throw URLError(code) }
            do { _ = try await makeClient().complete(sampleRequest()); return nil } catch { return error as? MuseError }
        }
        #expect(await fail(.notConnectedToInternet) == .offline)
        #expect(await fail(.networkConnectionLost) == .offline)
        #expect(await fail(.timedOut) == .timedOut)
    }

    @Test func theKeyNeverAppearsInTheRequestBody() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.handler = { _ in MockURLProtocol.respond(200, documentedResponse) }
        _ = try await makeClient(key: "super-secret-key").complete(sampleRequest())
        let body = String(decoding: try #require(MockURLProtocol.bodies.first), as: UTF8.self)
        #expect(!body.contains("super-secret-key"))
    }
}

struct CloudModelTests {
    @Test func cloudAnswerParsesStructuredAndFallsBackToRawText() {
        let structured = CloudAnswer.parse(#"{"answer":"Two things.","items":[{"title":"A","detail":"b","when":"","source_time":"12:30"}]}"#)
        #expect(structured.answer == "Two things." && structured.items.count == 1)

        #expect(CloudAnswer.parse(#"{"answer":"No items key"}"#).items.isEmpty)

        let raw = CloudAnswer.parse("Plain text, not JSON.")
        #expect(raw.answer == "Plain text, not JSON." && raw.items.isEmpty)
    }

    @Test func parsersTolerateCodeFencesAndSurroundingProse() {
        let json = #"{"answer":"Fenced.","items":[{"title":"A","detail":"b","when":"","source_time":"09:05"}]}"#
        #expect(CloudAnswer.parse("```json\n\(json)\n```").answer == "Fenced.")
        #expect(CloudAnswer.parse("Here you go:\n\(json)\nHope that helps.").items.count == 1)
        // Truncated JSON can't be read, so the raw text is shown instead of nothing.
        let truncated = CloudAnswer.parse(#"{"answer":"cut off"#)
        #expect(truncated.items.isEmpty && truncated.answer.contains("cut off"))

        let digest = #"{"day_summary":"x","conversations":[],"action_items":[],"people":[]}"#
        #expect(DayDigest.parse("```json\n\(digest)\n```")?.daySummary == "x")
        #expect(DayDigest.parse("not json") == nil)
    }

    @Test func stubIsAlwaysLabeledAndParsesIntoRealModels() async throws {
        let client = StubMuseClient()
        #expect(client.isStub)
        var promise = sampleRequest()
        promise.user = "Question: What did I promise people today?"
        let response = try await client.complete(promise)
        #expect(response.isStub && response.model == "stub")
        let answer = CloudAnswer.parse(response.content)
        #expect(answer.answer.hasPrefix("Stub preview"))
        #expect(answer.items.count >= 5)

        var digest = sampleRequest()
        digest.schemaName = EchoSchemas.digestName
        digest.schemaJSON = EchoSchemas.digest
        let digestResponse = try await client.complete(digest)
        let parsed = try #require(DayDigest.parse(digestResponse.content))
        #expect(parsed.conversations.count == 4 && !parsed.actionItems.isEmpty)
    }

    @Test func schemasAreValidJSONWithinMetasLimits() throws {
        for schema in [EchoSchemas.answer, EchoSchemas.digest] {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
            #expect(object["type"] as? String == "object")
            #expect(schema.count < 120_000)
        }
    }
}

struct APIKeyStoreTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-key-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadsAndTrimsTheKeyFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(APIKeyStore.load(directory: dir, environment: [:]) == nil)
        try "  abc123\n".write(to: dir.appending(path: "meta_api_key"), atomically: true, encoding: .utf8)
        #expect(APIKeyStore.load(directory: dir, environment: [:]) == "abc123")
    }

    @Test func environmentOverridesTheFileAndEmptyIsIgnored() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "from-file".write(to: dir.appending(path: "meta_api_key"), atomically: true, encoding: .utf8)
        #expect(APIKeyStore.load(directory: dir, environment: ["MODEL_API_KEY": "from-env"]) == "from-env")
        #expect(APIKeyStore.load(directory: dir, environment: ["MODEL_API_KEY": "  "]) == "from-file")
    }

    @Test func redactionHidesTheKey() {
        #expect(APIKeyStore.redacted("auth failed for sk-123 today", key: "sk-123") == "auth failed for ••• today")
        #expect(APIKeyStore.redacted("nothing here", key: nil) == "nothing here")
    }

    @Test func thePlaceholderBlankAndMalformedValuesAreNeverUsedAsAKey() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "meta_api_key")
        for bad in ["PASTE_YOUR_META_API_KEY_HERE", "PASTE_YOUR_META_API_KEY_HERE\n", "", "  \n ", "two words", "abc\ndef"] {
            try bad.write(to: file, atomically: true, encoding: .utf8)
            #expect(APIKeyStore.load(directory: dir, environment: [:]) == nil, "\(bad.debugDescription) must count as no key")
        }
        #expect(APIKeyStore.sanitized("PASTE_ANYTHING") == nil)
        #expect(APIKeyStore.sanitized("  real-key_123\n") == "real-key_123")
    }

    @Test func aPlaceholderInTheEnvironmentFallsBackToTheFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "from-file".write(to: dir.appending(path: "meta_api_key"), atomically: true, encoding: .utf8)
        #expect(APIKeyStore.load(directory: dir, environment: ["MODEL_API_KEY": "PASTE_YOUR_META_API_KEY_HERE"]) == "from-file")
    }

    @Test func withNoUsableKeyTheFactoryChoosesTheLabeledStub() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "PASTE_YOUR_META_API_KEY_HERE".write(to: dir.appending(path: "meta_api_key"), atomically: true, encoding: .utf8)
        // load() is what MuseClientFactory.make() consults; nil means StubMuseClient.
        #expect(APIKeyStore.load(directory: dir, environment: [:]) == nil)
    }
}
