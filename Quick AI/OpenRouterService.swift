import Foundation
import os

private let logger = Logger(subsystem: "com.quickai", category: "OpenRouter")

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

                    logger.info("Sending request to OpenRouter...")
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        logger.error("Invalid response (not HTTPURLResponse)")
                        continuation.finish(throwing: OpenRouterError.invalidResponse)
                        return
                    }

                    logger.info("HTTP status: \(http.statusCode)")

                    guard http.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        logger.error("API error \(http.statusCode): \(errorBody)")
                        continuation.finish(throwing: OpenRouterError.api(
                            statusCode: http.statusCode,
                            message: errorBody
                        ))
                        return
                    }

                    var lineCount = 0
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        lineCount += 1
                        if lineCount <= 5 {
                            logger.info("SSE line \(lineCount): \(line.prefix(200))")
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                            logger.info("Received [DONE] after \(lineCount) lines")
                            break
                        }

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String
                        else {
                            if lineCount <= 5 {
                                logger.warning("Failed to parse SSE payload: \(payload.prefix(200))")
                            }
                            continue
                        }

                        continuation.yield(content)
                    }

                    logger.info("Stream loop ended. Total lines: \(lineCount)")
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
