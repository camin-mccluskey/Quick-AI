# Homebrew Cask Release Workflow

Use this flow for every release.

## 1) Build a signed/notarized app

Export `Quick AI.app` from Xcode Organizer using your Developer ID.

## 2) Package and checksum

```bash
scripts/release/make-release.sh /path/to/Quick\ AI.app 1.0.0
```

Capture the printed SHA256.

## 3) Publish GitHub release

- Tag: `v1.0.0`
- Asset: `Quick-AI-1.0.0-macos.zip`

## 4) Update cask in tap repo

`Casks/quick-ai.rb`

```ruby
cask "quick-ai" do
  version "1.0.0"
  sha256 "<SHA256>"

  url "https://github.com/<org-or-user>/quick-ai/releases/download/v#{version}/Quick-AI-#{version}-macos.zip"
  name "Quick AI"
  desc "Instant AI answers from a global macOS hotkey"
  homepage "https://github.com/<org-or-user>/quick-ai"

  app "Quick AI.app"
end
```

## 5) Validate

```bash
brew uninstall --cask quick-ai || true
brew install --cask quick-ai
brew audit --cask quick-ai
```

## 6) Publish tap changes

Commit and push cask updates in your tap repo.
