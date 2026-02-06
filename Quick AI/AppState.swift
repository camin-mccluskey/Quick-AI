import SwiftUI

@Observable
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

        isLoading = true
        response = ""
        error = nil

        streamTask = Task {
            do {
                let stream = service.streamCompletion(
                    query: trimmed,
                    apiKey: apiKey,
                    model: selectedModel
                )
                for try await token in stream {
                    response += token
                }
            } catch is CancellationError {
                // expected on dismiss
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
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
