# Quick AI

Quick AI is a macOS menubar app that gives instant AI responses from a global hotkey (`Option+Space`).

It opens a lightweight overlay, streams responses inline, and stays out of the way when you're done.

## Features

- Menubar-only app (no Dock icon)
- Global hotkey toggle (`Option+Space`)
- Streaming OpenRouter responses
- Optional Brave Search grounding for fresh/current info
- API keys stored in macOS Keychain

## Requirements

- macOS 14+
- Xcode 16+
- OpenRouter API key
- Optional: Brave Search API key

## Local Development

```bash
# Build
xcodebuild -project "Quick AI.xcodeproj" -scheme "Quick AI" build

# Test
xcodebuild -project "Quick AI.xcodeproj" -scheme "Quick AI" test
```

## Settings

From the menu bar icon:

1. Open `Settings...`
2. Add your OpenRouter API key
3. Optionally add your Brave Search API key
4. Choose a model

## Releasing

### 1) Version bump

In Xcode target settings, update:

- `MARKETING_VERSION` (e.g. `1.0.0`)
- `CURRENT_PROJECT_VERSION` (build number)

### 2) Archive and export signed app

Use Xcode Organizer to archive and export `Quick AI.app` for distribution.

Notes:
- Use your Developer ID signing identity.
- Notarize before public distribution.

### 3) Package and checksum

After export, zip the app and compute sha256:

```bash
scripts/release/make-release.sh /path/to/Quick\ AI.app 1.0.0
```

This creates `dist/Quick-AI-1.0.0-macos.zip` and prints its SHA256.

### 4) GitHub release

Create a GitHub release `v1.0.0` and upload `Quick-AI-1.0.0-macos.zip`.

### 5) Homebrew cask

Create/update a cask in your tap repo (`homebrew-<tapname>`), e.g. `Casks/quick-ai.rb`:

```ruby
cask "quick-ai" do
  version "1.0.0"
  sha256 "<SHA256_FROM_SCRIPT>"

  url "https://github.com/<org-or-user>/quick-ai/releases/download/v#{version}/Quick-AI-#{version}-macos.zip"
  name "Quick AI"
  desc "Instant AI answers from a global macOS hotkey"
  homepage "https://github.com/<org-or-user>/quick-ai"

  app "Quick AI.app"
end
```

Test locally:

```bash
brew tap <org-or-user>/<tapname>
brew install --cask quick-ai
```

Users install with:

```bash
brew tap <org-or-user>/<tapname>
brew install --cask quick-ai
```

## Suggested Public Repo Checklist

- Add a `LICENSE` file
- Ensure app icon and metadata are final
- Remove personal/sensitive identifiers from project settings if desired
- Add release notes for each tagged version
- Keep cask `version`, `url`, and `sha256` updated per release

