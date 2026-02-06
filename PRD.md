# Product Requirements Document: Quick AI Lookup

## Overview
A lightweight macOS menubar app that provides instant AI responses to quick questions via a global hotkey. Built as a fast, minimal alternative to Google searches and AI chat interfaces.

## Core User Flow
1. User presses `Opt+Space` anywhere in macOS
2. Floating text input box appears at center-bottom of screen
3. User types question (e.g., "how do I reload my tmux config?")
4. AI response streams into the same window below the input
5. User reads answer, then clicks outside or presses `ESC` to dismiss
6. Window disappears completely - no persistent chat history

## Technical Stack
- **Language:** Swift
- **UI Framework:** SwiftUI with AppKit for global hotkey and overlay window
- **LLM Provider:** OpenRouter API
- **Model:** Gemini 2.0 Flash (or configurable)
- **Web Search Provider:** TBD - cheapest option (Brave Search API, Tavily, or SerpAPI)
- **Deployment:** Standalone macOS app

## Functional Requirements

### 1. Global Hotkey
- Register `Opt+Space` system-wide using Carbon/CGEvent
- Works regardless of active application
- Shows text input overlay when triggered

### 2. UI Components
**Input Window:**
- Floating overlay window (always on top)
- Positioned at center-bottom of screen
- Text input field at top
- Response area below (initially hidden)
- Modern macOS styling: blur background, subtle shadow, rounded corners
- Width: ~600px, height: adjusts based on response length (max ~800px with scroll)

**Visual States:**
- Input ready: Just shows text field
- Loading: Show subtle spinner/progress indicator
- Streaming: Response text appears incrementally as tokens arrive
- Complete: Full response displayed with syntax highlighting for code blocks

**Dismissal:**
- Click outside window
- Press `ESC`
- Press `Opt+Space` again (toggle behavior)

### 3. LLM Integration
**API Configuration:**
- OpenRouter API endpoint
- API key stored securely in macOS Keychain
- Configurable model selection (default: Gemini 2.0 Flash)

**System Prompt:**
```
You are a fast lookup assistant. Give brief, direct answers to questions. No pleasantries or lengthy explanations - just the essential information requested. Format code snippets with markdown when relevant. You have access to web search - use it when the query requires current information or facts you're uncertain about.
```

**Streaming:**
- Use Server-Sent Events (SSE) or streaming JSON from OpenRouter
- Display tokens as they arrive for perceived speed
- Handle connection errors gracefully with user-friendly error messages

**Error Handling:**
- API errors: Display clear error message in response area
- No fallback model - user must fix configuration or try again

### 4. Web Search Integration
**Priority:** Layer on after core LLM functionality is working

**Provider:** Cheapest available option
- Brave Search API (likely candidate)
- Tavily
- SerpAPI
- Decision based on cost per query

**Implementation:**
- LLM can trigger web search when needed via tool calling or function calling
- Search results injected into LLM context
- User sees only final answer (search process hidden)

### 5. Markdown Rendering
- Code blocks with syntax highlighting
- Basic markdown formatting (bold, italic, links, lists)
- Inline code styling
- Use SwiftUI Text with AttributedString or third-party markdown renderer

### 6. Settings/Configuration
**Menubar Icon:**
- Small menubar presence for settings access
- Preferences window with:
  - API key input (stored in Keychain, no validation on entry)
  - Model selection dropdown
  - Web search provider API key (when implemented)
  - Hotkey customization (future)
  - "Quit" option

**First Launch:**
- No onboarding flow
- Menubar icon appears
- User discovers preferences on their own
- First query attempt with missing API key shows error directing to preferences

### 7. Performance Targets
- App launch to ready state: <500ms
- Hotkey trigger to window display: <100ms
- First token from API: <500ms (model dependent)
- Memory footprint: <50MB idle

## Non-Functional Requirements

### Polish
- Smooth fade-in animation when window appears
- Native macOS look and feel (SF Pro font, system colors)
- Keyboard-first UX (Enter to submit, ESC to dismiss)
- Text selection/copy works in response area
- Window grows vertically as response streams in
- Scrollable response area when content exceeds 800px height

### Privacy
- No chat history stored
- API keys never logged
- No cost tracking displayed or stored
- Minimal telemetry (if any)

### Error Handling
- No API key configured: Show error message in response area with instruction to configure in preferences
- API error: Display error message from API or generic failure message
- Network timeout: Show timeout message, user must retry manually
- Invalid API key: Show authentication error on first use

## Out of Scope (v1)
- Chat history/persistence
- Multiple conversation threads
- Voice input
- Image/file upload
- Custom system prompts per query
- Multi-model comparison
- Cost tracking/analytics
- Automatic API key validation

## Implementation Timeline
1. **Phase 1 - Core Functionality**
   - Global hotkey registration
   - Floating window UI with input field
   - OpenRouter API integration
   - Response streaming and display
   - Basic markdown rendering with syntax highlighting
   - Menubar icon and preferences

2. **Phase 2 - Polish**
   - Animations and transitions
   - Error handling refinements
   - Window positioning and scrolling behavior
   - Keyboard shortcuts and UX improvements

3. **Phase 3 - Web Search**
   - Evaluate and select cheapest search provider
   - Integrate search API
   - Enable LLM tool calling for search
   - Testing and refinement

## Success Metrics
- Time from hotkey press to answer displayed: <2 seconds (p95)
- User completes query without switching to browser: >80%
- Answer satisfies query (user doesn't re-query): >70%
