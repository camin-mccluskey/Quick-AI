//
//  Quick_AITests.swift
//  Quick AITests
//
//  Created by Camin McCluskey on 05/02/2026.
//

import Testing
@testable import Quick_AI

struct Quick_AITests {
    @Test
    func renderMarkdownPreservesPlainTextContent() {
        let rendered = AppState.renderMarkdown(from: "hello world")
        #expect(String(rendered.characters) == "hello world")
    }

    @Test
    func openRouterErrorMessagesMapCommonCodes() {
        #expect(OpenRouterError.api(statusCode: 401, message: "x").errorDescription == "Invalid API key. Check your key in Settings.")
        #expect(OpenRouterError.api(statusCode: 429, message: "x").errorDescription == "Rate limited. Please wait a moment and try again.")
        #expect(OpenRouterError.api(statusCode: 418, message: "teapot").errorDescription == "OpenRouter error (418): teapot")
    }
}
