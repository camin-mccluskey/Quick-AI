# Quick AI

Quick AI is a production macOS menubar assistant for instant AI answers.

Press `Option+Space`, type your prompt, and get a streamed response in a lightweight overlay without leaving your current app.

## Highlights

- Menubar-only app (no Dock icon)
- Global hotkey toggle: `Option+Space`
- Streaming responses through OpenRouter
- Optional Brave Search grounding for up-to-date questions
- API keys stored securely in macOS Keychain
- No persistent chat history in the app

## Requirements

- macOS 14 or newer
- OpenRouter API key
- Optional: Brave Search API key (for web-grounded answers)

## Install

```bash
brew install --cask camin-mccluskey/tap/quick-ai
```

## First Run

1. Launch `Quick AI`.
2. Open the menubar icon and choose `Settings...`.
3. Add your OpenRouter API key.
4. Optionally add a Brave Search API key.
5. Select your preferred model.
6. Use `Option+Space` anywhere to open/close the overlay.
