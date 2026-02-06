import SwiftUI
import os

private let logger = Logger(subsystem: "com.quickai", category: "AppState")

@Observable
@MainActor
final class AppState {
    var query = ""
    var response = ""
    var isLoading = false
    var error: String?

    private let service = OpenRouterService()
    private var streamTask: Task<Void, Never>?

    var selectedModel: String {
        get { UserDefaults.standard.string(forKey: "selectedModel") ?? "google/gemini-2.0-flash-001" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedModel") }
    }

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        guard let apiKey = KeychainManager.load(key: "openrouter-api-key"), !apiKey.isEmpty else {
            error = "No API key configured. Click the menubar icon → Settings to add your OpenRouter API key."
            return
        }

        streamTask?.cancel()

        logger.info("submit() called with query: \(trimmed), model: \(self.selectedModel)")
        isLoading = true
        response = ""
        error = nil

        let model = selectedModel
        streamTask = Task { @MainActor in
            defer {
                isLoading = false
                streamTask = nil
                logger.info("isLoading set to false")
            }

            do {
                logger.info("Starting stream...")
                let stream = service.streamCompletion(
                    query: trimmed,
                    apiKey: apiKey,
                    model: model
                )

                var tokenCount = 0
                for try await token in stream {
                    tokenCount += 1
                    response += token
                    if tokenCount <= 3 {
                        logger.info("Token \(tokenCount): \(token)")
                    }
                }

                logger.info("Stream finished. Total tokens: \(tokenCount), response length: \(self.response.count)")
            } catch is CancellationError {
                logger.info("Stream cancelled")
            } catch {
                logger.error("Stream error: \(error.localizedDescription)")
                self.error = error.localizedDescription
            }
        }
    }

    func reset() {
        streamTask?.cancel()
        streamTask = nil
        query = ""
        response = ""
        isLoading = false
        error = nil
    }
}
