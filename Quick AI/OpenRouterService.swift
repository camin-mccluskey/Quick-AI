import Foundation

protocol SearchProvider {
    func search(query: String) async throws -> SearchResponse
}

struct SearchResponse {
    let query: String
    let results: [SearchResult]

    struct SearchResult {
        let title: String
        let url: String
        let snippet: String
    }
}

struct BraveSearchProvider: SearchProvider {
    private let apiKey: String
    private let endpoint = URL(string: "https://api.search.brave.com/res/v1/web/search")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func search(query: String) async throws -> SearchResponse {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "5"),
        ]

        guard let url = components?.url else {
            throw SearchProviderError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SearchProviderError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw SearchProviderError.api(
                statusCode: http.statusCode,
                message: Self.extractAPIErrorMessage(from: data)
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let rawResults = web["results"] as? [[String: Any]]
        else {
            throw SearchProviderError.invalidResponse
        }

        let results = rawResults.compactMap { result -> SearchResponse.SearchResult? in
            guard let title = result["title"] as? String,
                  let url = result["url"] as? String
            else {
                return nil
            }

            let snippet = (result["description"] as? String) ?? ""
            return SearchResponse.SearchResult(title: title, url: url, snippet: snippet)
        }

        return SearchResponse(query: query, results: Array(results.prefix(5)))
    }

    private static func extractAPIErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unexpected search API error."
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        return String(data: data, encoding: .utf8) ?? "Unexpected search API error."
    }
}

enum SearchProviderError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid search request."
        case .invalidResponse:
            return "Invalid response from search provider."
        case let .api(statusCode, message):
            switch statusCode {
            case 401, 403:
                return "Invalid Brave Search API key. Check your key in Settings."
            case 429:
                return "Search provider rate limited. Please wait a moment and try again."
            default:
                return "Search provider error (\(statusCode)): \(message)"
            }
        }
    }
}

struct OpenRouterService {
    private let endpoint: URL
    private let session: URLSession

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    private static let systemPrompt = """
        You are a fast lookup assistant. Give brief, direct answers to questions. \
        No pleasantries or lengthy explanations - just the essential information requested. \
        Format code snippets with markdown when relevant. \
        Use web search only when the answer likely depends on current events or information that may be newer than your training cutoff.
        """

    private static let webSearchTool: [String: Any] = [
        "type": "function",
        "function": [
            "name": "web_search",
            "description": "Search the web for current facts and recent events.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Search query to run",
                    ],
                ],
                "required": ["query"],
            ],
        ],
    ]

    func streamCompletion(
        query: String,
        apiKey: String,
        model: String,
        searchProvider: SearchProvider? = nil,
        onSearchActivityChanged: @escaping @Sendable (Bool) -> Void = { _ in }
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let searchProvider {
                        try await completeWithOptionalSearch(
                            query: query,
                            apiKey: apiKey,
                            model: model,
                            searchProvider: searchProvider,
                            onSearchActivityChanged: onSearchActivityChanged,
                            continuation: continuation
                        )
                    } else {
                        let baseMessages: [[String: Any]] = [
                            ["role": "system", "content": Self.systemPrompt],
                            ["role": "user", "content": query],
                        ]
                        try await streamResponse(
                            messages: baseMessages,
                            apiKey: apiKey,
                            model: model,
                            continuation: continuation
                        )
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func completeWithOptionalSearch(
        query: String,
        apiKey: String,
        model: String,
        searchProvider: SearchProvider,
        onSearchActivityChanged: @escaping @Sendable (Bool) -> Void,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var messages: [[String: Any]] = [
            ["role": "system", "content": Self.systemPrompt],
            ["role": "user", "content": query],
        ]

        let probeResponse = try await runCompletion(
            messages: messages,
            apiKey: apiKey,
            model: model,
            stream: false,
            tools: [Self.webSearchTool]
        )

        let toolCalls = Self.extractToolCalls(from: probeResponse)
        guard !toolCalls.isEmpty else {
            if let content = Self.extractAssistantContent(from: probeResponse), !content.isEmpty {
                continuation.yield(content)
            } else {
                try await streamResponse(
                    messages: messages,
                    apiKey: apiKey,
                    model: model,
                    continuation: continuation
                )
            }
            return
        }

        messages.append([
            "role": "assistant",
            "content": "",
            "tool_calls": toolCalls.map(\.raw),
        ])

        for toolCall in toolCalls {
            guard toolCall.name == "web_search" else { continue }
            let searchQuery = toolCall.arguments["query"] as? String ?? query
            onSearchActivityChanged(true)
            defer { onSearchActivityChanged(false) }
            let searchResponse = try await searchProvider.search(query: searchQuery)
            let content = Self.serializeSearchResponse(searchResponse)

            messages.append([
                "role": "tool",
                "tool_call_id": toolCall.id,
                "name": "web_search",
                "content": content,
            ])
        }

        try await streamResponse(
            messages: messages,
            apiKey: apiKey,
            model: model,
            continuation: continuation
        )
    }

    private func runCompletion(
        messages: [[String: Any]],
        apiKey: String,
        model: String,
        stream: Bool,
        tools: [[String: Any]]? = nil
    ) async throws -> Any {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": messages,
        ]

        if let tools {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw OpenRouterError.api(
                statusCode: http.statusCode,
                message: Self.extractAPIErrorMessage(from: data)
            )
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    private func streamResponse(
        messages: [[String: Any]],
        apiKey: String,
        model: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard http.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw OpenRouterError.api(
                statusCode: http.statusCode,
                message: Self.extractAPIErrorMessage(from: errorBody)
            )
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                break
            }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String
            else {
                continue
            }

            continuation.yield(content)
        }
    }

    private static func extractToolCalls(from response: Any) -> [ToolCall] {
        guard let json = response as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let rawToolCalls = message["tool_calls"] as? [[String: Any]]
        else {
            return []
        }

        return rawToolCalls.compactMap { raw in
            guard let id = raw["id"] as? String,
                  let function = raw["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let argumentsJSON = function["arguments"] as? String,
                  let argumentsData = argumentsJSON.data(using: .utf8),
                  let arguments = (try? JSONSerialization.jsonObject(with: argumentsData)) as? [String: Any]
            else {
                return nil
            }

            return ToolCall(id: id, name: name, arguments: arguments, raw: raw)
        }
    }

    private static func extractAssistantContent(from response: Any) -> String? {
        guard let json = response as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else {
            return nil
        }

        return message["content"] as? String
    }

    private static func serializeSearchResponse(_ response: SearchResponse) -> String {
        let payload: [String: Any] = [
            "query": response.query,
            "results": response.results.map {
                [
                    "title": $0.title,
                    "url": $0.url,
                    "snippet": $0.snippet,
                ]
            },
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"query\":\"\(response.query)\",\"results\":[]}"
        }

        return string
    }

    private static func extractAPIErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unexpected API error."
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        return String(data: data, encoding: .utf8) ?? "Unexpected API error."
    }

    private static func extractAPIErrorMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8) else {
            return body.isEmpty ? "Unexpected API error." : body
        }

        return extractAPIErrorMessage(from: data)
    }

    private struct ToolCall {
        let id: String
        let name: String
        let arguments: [String: Any]
        let raw: [String: Any]
    }
}

enum OpenRouterError: LocalizedError {
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenRouter."
        case let .api(code, message):
            switch code {
            case 401:
                return "Invalid API key. Check your key in Settings."
            case 402:
                return "Billing or credit issue. Check your OpenRouter account balance."
            case 429:
                return "Rate limited. Please wait a moment and try again."
            case 500...599:
                return "OpenRouter is temporarily unavailable (\(code)). Please try again."
            default:
                return "OpenRouter error (\(code)): \(message)"
            }
        }
    }
}
