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
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.finish(throwing: OpenRouterError.api(
                            statusCode: http.statusCode,
                            message: Self.extractAPIErrorMessage(from: errorBody)
                        ))
                        return
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

    private static func extractAPIErrorMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return body.isEmpty ? "Unexpected API error." : body
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        return body.isEmpty ? "Unexpected API error." : body
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
