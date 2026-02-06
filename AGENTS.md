# AGENTS.MD

This file provides guidance to AI agents (Claude Code, OpenAI Codex, Opencode etc) when working with code in this repository.

## Project Overview

Quick AI is a macOS menubar app that provides instant AI responses via a global hotkey (`Opt+Space`). It's a lightweight alternative to browser-based AI chat — a floating overlay window appears, the user types a question, and a streamed response appears inline. No persistent chat history. See `PRD.md` for full product requirements.

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI + AppKit (for global hotkey registration and overlay window management)
- **LLM:** OpenRouter API (default model: Gemini 2.0 Flash), streamed via SSE
- **API keys:** Stored in macOS Keychain
- **Testing:** Swift Testing framework (unit tests), XCTest (UI tests)

## Build & Run

This is an Xcode project (`Quick AI.xcodeproj`) with scheme `Quick AI`. Note: paths contain spaces.

```bash
# Build
xcodebuild -project "Quick AI.xcodeproj" -scheme "Quick AI" build

# Run tests
xcodebuild -project "Quick AI.xcodeproj" -scheme "Quick AI" test

# Run a single test (by name)
xcodebuild -project "Quick AI.xcodeproj" -scheme "Quick AI" test -only-testing:"Quick AITests/Quick_AITests/testName"
```

Requires Xcode (not just Command Line Tools) with the active developer directory pointed at Xcode.app.

## Project Structure

- `Quick AI/` — Main app target
  - `Quick_AIApp.swift` — App entry point (`@main`)
  - `ContentView.swift` — Root SwiftUI view
  - `Persistence.swift` — Core Data stack (currently Xcode template; likely to be removed per PRD's "no persistence" requirement)
  - `Quick_AI.xcdatamodeld/` — Core Data model (template `Item` entity)
- `Quick AITests/` — Unit tests (Swift Testing framework, `@Test` macro)
- `Quick AIUITests/` — UI tests (XCTest, includes launch performance test)

## Current State

The project is at Xcode template stage. The PRD describes the target architecture which includes:
- Global hotkey registration via Carbon/CGEvent
- Floating overlay window (always-on-top, center-bottom positioning)
- OpenRouter API integration with SSE streaming
- Markdown rendering with syntax highlighting
- Menubar-only presence (no dock icon) with settings/preferences
- Web search integration (Phase 3, provider TBD)

## Architecture Notes

- This is a **menubar app** — it should use `NSStatusItem` for the menubar icon and should not appear in the Dock. The app entry point will need to shift from a standard `WindowGroup` to an AppKit-managed overlay window.
- The Core Data stack (`Persistence.swift`, `Quick_AI.xcdatamodeld`) is from the Xcode template and should be removed — the PRD explicitly states no chat history/persistence.
- The module name is `Quick_AI` (underscored) due to the space in the project name. Use `@testable import Quick_AI` in tests.
