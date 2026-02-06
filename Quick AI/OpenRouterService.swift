import Foundation

struct OpenRouterService {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    private static let systemPrompt = """
        You are a fast lookup assistant. Give brief, direct answers to questions. \
        No pleasantries or lengthy explanations - just the essential information requested. \
        Format code snippets with markdown when relevant.
        """

    func streamCompletion(
        query: String,
        apiKey: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": Self.systemPrompt],
                            ["role": "user", "content": query],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: OpenRouterError.invalidResponse)
                        return
                    }

                    guard http.statusCode == 200 else {
                        // Try to read error body
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.finish(throwing: OpenRouterError.api(
                            statusCode: http.statusCode,
                            message: errorBody
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String
                        else { continue }

                        continuation.yield(content)
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
}

enum OpenRouterError: LocalizedError {
    case invalidResponse
    case api(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenRouter."
        case .api(let code, let message):
            if code == 401 {
                return "Invalid API key. Check your key in Settings."
            }
            return "OpenRouter error (\(code)): \(message)"
        }
    }
}
