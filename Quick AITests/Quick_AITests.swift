//
//  Quick_AITests.swift
//  Quick AITests
//
//  Created by Camin McCluskey on 05/02/2026.
//

import Foundation
import Testing
@testable import Quick_AI

@Suite(.serialized)
struct Quick_AITests {
    @MainActor
    @Test
    func submitIgnoresWhitespaceQuery() {
        let state = AppState()
        state.query = "   \n\t"

        state.submit()

        #expect(state.isLoading == false)
        #expect(state.error == nil)
        #expect(state.response.isEmpty)
    }

    @MainActor
    @Test
    func submitWithoutAPIKeyShowsConfigurationError() {
        setenv("QUICK_AI_KEYCHAIN_SERVICE", "tests.quickai.\(UUID().uuidString)", 1)
        defer { unsetenv("QUICK_AI_KEYCHAIN_SERVICE") }

        let state = AppState()
        state.query = "hello"

        state.submit()

        #expect(state.isLoading == false)
        #expect(state.error?.contains("No API key configured") == true)
    }

    @MainActor
    @Test
    func selectedModelPersistsViaAppDefaultsSuite() {
        let suite = "tests.quickai.defaults.\(UUID().uuidString)"
        setenv("QUICK_AI_DEFAULTS_SUITE", suite, 1)
        defer {
            unsetenv("QUICK_AI_DEFAULTS_SUITE")
            if let defaults = UserDefaults(suiteName: suite) {
                defaults.removePersistentDomain(forName: suite)
                defaults.synchronize()
            }
        }

        let first = AppState()
        first.selectedModel = "openai/gpt-4o-mini"

        let second = AppState()
        #expect(second.selectedModel == "openai/gpt-4o-mini")
    }

    @MainActor
    @Test
    func resetClearsTransientState() {
        let state = AppState()
        state.query = "q"
        state.response = "r"
        state.renderedResponse = AttributedString("rendered")
        state.isLoading = true
        state.isSearchingWeb = true
        state.error = "err"

        state.reset()

        #expect(state.query.isEmpty)
        #expect(state.response.isEmpty)
        #expect(String(state.renderedResponse.characters).isEmpty)
        #expect(state.isLoading == false)
        #expect(state.isSearchingWeb == false)
        #expect(state.error == nil)
    }

    @Test
    func renderMarkdownPreservesReadableContent() {
        let rendered = AppState.renderMarkdown(from: "**hello** world")
        #expect(String(rendered.characters).contains("hello world"))
    }

    @Test
    func openRouterErrorMessagesMapCommonCodes() {
        #expect(OpenRouterError.api(statusCode: 401, message: "x").errorDescription == "Invalid API key. Check your key in Settings.")
        #expect(OpenRouterError.api(statusCode: 402, message: "x").errorDescription == "Billing or credit issue. Check your OpenRouter account balance.")
        #expect(OpenRouterError.api(statusCode: 429, message: "x").errorDescription == "Rate limited. Please wait a moment and try again.")
        #expect(OpenRouterError.api(statusCode: 503, message: "x").errorDescription == "OpenRouter is temporarily unavailable (503). Please try again.")
        #expect(OpenRouterError.api(statusCode: 418, message: "teapot").errorDescription == "OpenRouter error (418): teapot")
    }

    @Test
    func searchProviderErrorMessagesMapCommonCodes() {
        #expect(SearchProviderError.api(statusCode: 401, message: "x").errorDescription == "Invalid Brave Search API key. Check your key in Settings.")
        #expect(SearchProviderError.api(statusCode: 403, message: "x").errorDescription == "Invalid Brave Search API key. Check your key in Settings.")
        #expect(SearchProviderError.api(statusCode: 429, message: "x").errorDescription == "Search provider rate limited. Please wait a moment and try again.")
        #expect(SearchProviderError.api(statusCode: 500, message: "boom").errorDescription == "Search provider error (500): boom")
    }

    @Test
    func keychainSaveLoadUpdateDeleteRoundTrip() {
        setenv("QUICK_AI_KEYCHAIN_SERVICE", "tests.quickai.\(UUID().uuidString)", 1)
        defer { unsetenv("QUICK_AI_KEYCHAIN_SERVICE") }

        let key = "openrouter-api-key"
        #expect(KeychainManager.delete(key: key) == true)
        #expect(KeychainManager.save(key: key, value: "value-1") == true)
        #expect(KeychainManager.load(key: key) == "value-1")
        #expect(KeychainManager.save(key: key, value: "value-2") == true)
        #expect(KeychainManager.load(key: key) == "value-2")
        #expect(KeychainManager.delete(key: key) == true)
        #expect(KeychainManager.load(key: key) == nil)
    }

    @Test
    func streamCompletionYieldsSSETokensUntilDone() async throws {
        URLProtocolMock.reset()
        URLProtocolMock.enqueue { request in
            let body = try jsonBody(from: request)
            #expect((body["stream"] as? Bool) == true)
            #expect((body["model"] as? String) == "model")

            let sse = """
            data: {"choices":[{"delta":{"content":"Hello "}}]}
            data: {"choices":[{"delta":{"content":"world"}}]}
            data: [DONE]

            """
            return (httpResponse(statusCode: 200, for: request), Data(sse.utf8))
        }

        let service = await OpenRouterService(session: makeMockedSession())
        let stream = await service.streamCompletion(query: "hi", apiKey: "k", model: "model")

        var output = ""
        for try await token in stream {
            output += token
        }

        #expect(output == "Hello world")
    }

    @Test
    func streamCompletionPropagatesAPIErrorBody() async {
        URLProtocolMock.reset()
        URLProtocolMock.enqueue { request in
            let body = try jsonBody(from: request)
            #expect((body["stream"] as? Bool) == true)

            let payload = #"{"error":{"message":"bad key"}}"#
            return (httpResponse(statusCode: 401, for: request), Data(payload.utf8))
        }

        let service = await OpenRouterService(session: makeMockedSession())
        let stream = await service.streamCompletion(query: "hi", apiKey: "k", model: "model")

        do {
            for try await _ in stream {}
            Issue.record("Expected stream to fail for non-200 response")
        } catch {
            guard let routerError = error as? OpenRouterError else {
                Issue.record("Unexpected error type: \(error)")
                return
            }
            guard case let OpenRouterError.api(statusCode, message) = routerError else {
                Issue.record("Unexpected OpenRouterError case: \(routerError)")
                return
            }
            #expect(statusCode == 401)
            #expect(message == "bad key")
        }
    }

    @Test
    func streamCompletionRunsToolCallThenStreamsFinalResponse() async throws {
        URLProtocolMock.reset()
        let recorder = SearchActivityRecorder()
        let fakeSearch = FakeSearchProvider()

        URLProtocolMock.enqueue { request in
            let body = try jsonBody(from: request)
            #expect((body["stream"] as? Bool) == false)
            #expect((body["tools"] as? [[String: Any]])?.isEmpty == false)

            let probe = """
            {
              "choices": [
                {
                  "message": {
                    "tool_calls": [
                      {
                        "id": "call_1",
                        "function": {
                          "name": "web_search",
                          "arguments": "{\\"query\\":\\"swift release date\\"}"
                        }
                      }
                    ]
                  }
                }
              ]
            }
            """

            return (httpResponse(statusCode: 200, for: request), Data(probe.utf8))
        }

        URLProtocolMock.enqueue { request in
            let body = try jsonBody(from: request)
            #expect((body["stream"] as? Bool) == true)
            guard let messages = body["messages"] as? [[String: Any]] else {
                Issue.record("Expected messages in second request")
                return (httpResponse(statusCode: 500, for: request), Data())
            }

            let hasToolResult = messages.contains { message in
                (message["role"] as? String) == "tool"
                    && (message["name"] as? String) == "web_search"
                    && ((message["content"] as? String)?.contains("swift release date") == true)
            }
            #expect(hasToolResult)

            let sse = """
            data: {"choices":[{"delta":{"content":"Current info"}}]}
            data: [DONE]

            """
            return (httpResponse(statusCode: 200, for: request), Data(sse.utf8))
        }

        let service = await OpenRouterService(session: makeMockedSession())
        let stream = await service.streamCompletion(
            query: "When was swift released?",
            apiKey: "k",
            model: "model",
            searchProvider: fakeSearch,
            onSearchActivityChanged: { value in
                Task { await recorder.record(value) }
            }
        )

        var output = ""
        for try await token in stream {
            output += token
        }

        try? await Task.sleep(for: .milliseconds(50))

        #expect(output == "Current info")
        #expect(await fakeSearch.recordedQueries() == ["swift release date"])
        #expect(await recorder.values() == [true, false])
    }
}

private func makeMockedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolMock.self]
    return URLSession(configuration: configuration)
}

private func jsonBody(from request: URLRequest) throws -> [String: Any] {
    let data: Data
    if let body = request.httpBody {
        data = body
    } else if let stream = request.httpBodyStream {
        data = try readBodyStream(stream)
    } else {
        throw NSError(domain: "QuickAITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing request body"])
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(domain: "QuickAITests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON body"])
    }
    return json
}

private func readBodyStream(_ stream: InputStream) throws -> Data {
    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read < 0 {
            throw stream.streamError ?? NSError(domain: "QuickAITests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed reading request body stream"])
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data
}

private func httpResponse(statusCode: Int, for request: URLRequest) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url ?? URL(string: "https://example.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private final class URLProtocolMock: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handlers: [(URLRequest) throws -> (HTTPURLResponse, Data)] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    static func enqueue(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        handlers.append(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "openrouter.ai"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        Self.lock.lock()
        if Self.handlers.isEmpty {
            handler = nil
        } else {
            handler = Self.handlers.removeFirst()
        }
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "QuickAITests", code: 3))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor FakeSearchProvider: SearchProvider {
    private var queries: [String] = []

    func search(query: String) async throws -> SearchResponse {
        queries.append(query)
        return SearchResponse(
            query: query,
            results: [
                .init(title: "Swift", url: "https://swift.org", snippet: "Swift language")
            ]
        )
    }

    func recordedQueries() -> [String] {
        queries
    }
}

private actor SearchActivityRecorder {
    private var storage: [Bool] = []

    func record(_ value: Bool) {
        storage.append(value)
    }

    func values() -> [Bool] {
        storage
    }
}
