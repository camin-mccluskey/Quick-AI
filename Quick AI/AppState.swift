import SwiftUI
import os

private let logger = Logger(subsystem: "com.quickai", category: "AppState")

enum AppDefaults {
    static var shared: UserDefaults {
        guard let suiteName = ProcessInfo.processInfo.environment["QUICK_AI_DEFAULTS_SUITE"],
              !suiteName.isEmpty,
              let defaults = UserDefaults(suiteName: suiteName)
        else {
            return .standard
        }
        return defaults
    }
}

@Observable
@MainActor
final class AppState {
    var query = ""
    var response = ""
    var renderedResponse = AttributedString("")
    var isLoading = false
    var isSearchingWeb = false
    var error: String?

    private let service = OpenRouterService()
    private var streamTask: Task<Void, Never>?
    private var markdownRenderTask: Task<Void, Never>?

    var selectedModel: String {
        get { AppDefaults.shared.string(forKey: "selectedModel") ?? "google/gemini-2.0-flash-001" }
        set { AppDefaults.shared.set(newValue, forKey: "selectedModel") }
    }

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let apiKey = KeychainManager.load(key: "openrouter-api-key"), !apiKey.isEmpty else {
            error = "No API key configured. Click the menubar icon -> Settings to add your OpenRouter API key."
            return
        }

        streamTask?.cancel()
        markdownRenderTask?.cancel()

        isLoading = true
        response = ""
        renderedResponse = AttributedString("")
        error = nil

        let model = selectedModel
        streamTask = Task { @MainActor in
            defer {
                isLoading = false
                isSearchingWeb = false
                streamTask = nil
            }

            do {
                let searchProvider: SearchProvider? = {
                    guard let searchAPIKey = KeychainManager.load(key: "brave-search-api-key"), !searchAPIKey.isEmpty else {
                        return nil
                    }
                    return BraveSearchProvider(apiKey: searchAPIKey)
                }()

                let stream = service.streamCompletion(
                    query: trimmed,
                    apiKey: apiKey,
                    model: model,
                    searchProvider: searchProvider,
                    onSearchActivityChanged: { [weak self] isSearching in
                        Task { @MainActor in
                            self?.isSearchingWeb = isSearching
                        }
                    }
                )

                for try await token in stream {
                    response += token
                    scheduleMarkdownRender()
                }

                await renderFinalMarkdown()
            } catch is CancellationError {
                logger.debug("Stream cancelled")
            } catch {
                logger.error("Stream error: \(error.localizedDescription)")
                self.error = userFacingErrorMessage(for: error)
            }
        }
    }

    func reset() {
        streamTask?.cancel()
        markdownRenderTask?.cancel()
        streamTask = nil
        markdownRenderTask = nil
        query = ""
        response = ""
        renderedResponse = AttributedString("")
        isLoading = false
        isSearchingWeb = false
        error = nil
    }

    nonisolated static func renderMarkdown(from text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(text)
    }

    private func scheduleMarkdownRender() {
        markdownRenderTask?.cancel()
        let snapshot = response

        markdownRenderTask = Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .utility) {
                Self.renderMarkdown(from: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            self.renderedResponse = rendered
        }
    }

    private func renderFinalMarkdown() async {
        markdownRenderTask?.cancel()
        let snapshot = response
        let rendered = await Task.detached(priority: .userInitiated) {
            Self.renderMarkdown(from: snapshot)
        }.value
        renderedResponse = rendered
        markdownRenderTask = nil
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection. Check your network and try again."
            case .timedOut:
                return "Request timed out. Try again."
            case .cannotFindHost, .cannotConnectToHost:
                return "Could not reach OpenRouter. Try again in a moment."
            default:
                break
            }
        }

        return "Something went wrong. Please try again."
    }
}
