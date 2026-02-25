# Conversation Assistant

A real-time AI-powered macOS assistant that listens to conversations, transcribes speech on the fly, and generates intelligent responses using Claude. Integrates with Confluence, Jira, and GitHub to pull context from your knowledge base.

Built with pure Swift and native macOS frameworks — no Electron, no Python, no web views.

<video src="https://github.com/kaizen-yutani/conversation-assistant/raw/main/demo.mp4" width="100%" autoplay loop muted playsinline></video>

## How It Works

The app captures audio from your microphone and system output (Zoom, Teams, etc.), runs voice activity detection on-device with Silero VAD, streams detected speech to Deepgram for transcription, then routes transcribed questions to Claude with optional tool calls against your connected services.

```
Mic / System Audio
    → Silero VAD (on-device, CoreML)
    → Deepgram Nova-3 (streaming STT, ~100ms)
    → Claude Haiku (response generation)
    → Tool calls: Confluence, Jira, GitHub, web search, database
```

End-to-end latency from speech to first response token is typically under 1.5 seconds.

## Features

- **Real-time voice transcription** — Dual audio capture (microphone + system audio) with Deepgram Nova-3 streaming and Groq Whisper fallback
- **On-device VAD** — Silero VAD via CoreML for low-latency speech detection without sending audio to the cloud until speech is confirmed
- **AI responses** — Claude generates concise, contextual answers as the conversation happens
- **Knowledge base integration** — Searches Confluence docs, Jira tickets, GitHub repos, databases, and the web via natural language
- **Screenshot analysis** — Capture and analyze code, diagrams, or documents with Claude's vision
- **Speaker detection** — Classifies who is speaking based on audio source
- **Multi-language** — 11 languages including English, German, Spanish, French, Russian, Chinese, Japanese, Korean
- **Conversation context** — Multi-turn history with automatic summarization
- **Floating window** — Translucent, always-on-top window that stays out of the way

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac
- API keys: [Anthropic](https://console.anthropic.com) (required), [Deepgram](https://console.deepgram.com) (recommended), [Groq](https://console.groq.com) (optional fallback)

## Quick Start

```bash
git clone https://github.com/kaizen-yutani/conversation-assistant.git
cd conversation-assistant
./build.sh
```

The build script compiles all Swift sources, bundles the app with the Silero VAD model, signs it (Developer ID if available, ad-hoc otherwise), and opens it.

On first launch the app will prompt you to:
1. Grant **Microphone** and **Screen Recording** permissions
2. Enter your API keys
3. Optionally connect Atlassian and GitHub via OAuth

## Configuration

### API Keys

Create `~/.conversation-assistant-keys`:

```
ANTHROPIC_API_KEY=sk-ant-...
DEEPGRAM_API_KEY=...
GROQ_API_KEY=gsk_...
```

The file is automatically restricted to `chmod 600`. At minimum you need `ANTHROPIC_API_KEY`. Add `DEEPGRAM_API_KEY` for streaming transcription or `GROQ_API_KEY` for batch.

### OAuth Integrations (Optional)

Confluence/Jira and GitHub integrations use OAuth with PKCE. The app runs a local callback server on port 9876 during authorization. Create `~/.conversation-assistant-oauth` with your OAuth app credentials:

```
ATLASSIAN_CLIENT_ID=...
ATLASSIAN_CLIENT_SECRET=...
GITHUB_CLIENT_ID=...
GITHUB_CLIENT_SECRET=...
```

Or use the in-app onboarding flow to set these up.

### Data Sources (Optional)

For database and web search, create `~/.conversation-assistant-secrets`:

```
DATABASE_URL=postgresql://user:pass@host:5432/db
WEB_SEARCH_API_KEY=...
```

## Tool Integrations

When connected, Claude can call 17 tools to answer questions:

| Category | Tools |
|----------|-------|
| **Confluence** | Search docs, list spaces, get page content, create pages |
| **Jira** | Search tickets, list projects/boards, get sprint info, create issues, add comments |
| **GitHub** | Search code/PRs/issues, list repos/branches, get PR and issue details |
| **Database** | Natural language queries translated to SQL |
| **Web** | Search the web for external information |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+B` | Toggle window visibility |
| `Cmd+1` | Notes tab |
| `Cmd+2` | Coding Task tab |
| `Cmd+3` | Voice Assistant tab |
| `Cmd+S` | Capture screenshot |
| `Cmd+Enter` | Analyze screenshots |
| `Cmd+F` | Search notes |
| `Cmd+\` | Toggle floating solution window |
| `Cmd+,` | Settings |

## Architecture

```
conversation_assistant.swift          # App entry and main delegate
Domain/
  Model/                              # Core data models, settings, conversation context
  ValueObjects/                       # Enums (tabs, analysis modes)
  Entities/                           # Domain entities (screenshots)
Application/
  UseCases/                           # Business logic
Infrastructure/
  API/                                # Anthropic & OpenAI streaming clients
  Speech/                             # VAD, Deepgram WebSocket, Groq STT, keyword matching
  Auth/                               # OAuth with PKCE (Atlassian, GitHub)
  Storage/                            # File-based key management
  Tools/                              # Tool system with 5 integration clients
Presentation/
  Settings/                           # Settings window
  Windows/                            # Window factory, floating windows
  Onboarding/                         # Permission & OAuth setup flows
  Timeline/                           # Message rendering and streaming
  Styling/                            # Markdown renderer, syntax highlighting
```

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | 0.14.1 | On-device speech recognition |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | 0.1.15 | ML model support for WhisperKit |
| [Jinja](https://github.com/johnmai-dev/Jinja) | 1.3.0 | Template engine for WhisperKit |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.6.2 | CLI argument handling |
| [swift-collections](https://github.com/apple/swift-collections) | 1.3.0 | Data structure utilities |

### System Frameworks

Cocoa, Carbon, ScreenCaptureKit, AVFoundation, Speech, Security, Network, CoreML, Accelerate

## Building for Release

Release builds require an Apple Developer ID certificate:

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)"
./build-release.sh
./create-dmg.sh
```

For notarization:

```bash
export APPLE_ID="your@email.com"
export TEAM_ID="YOUR_TEAM_ID"
./notarize.sh
```

## Privacy

- All data stays on your device by default
- Audio is sent to Deepgram/Groq for transcription only when recording is active
- Screenshots are sent to Anthropic only when you trigger analysis
- API keys are stored locally with `chmod 600` file permissions
- No telemetry, analytics, or tracking

See [PRIVACY_POLICY.md](PRIVACY_POLICY.md) for full details.

## Acknowledgments

- [Silero VAD](https://github.com/snakers4/silero-vad) — On-device voice activity detection (MIT License)
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax — On-device speech recognition
- [Claude](https://www.anthropic.com/claude) by Anthropic — AI response generation
- [Deepgram](https://deepgram.com) — Streaming speech-to-text
- [Groq](https://groq.com) — Fast Whisper inference

## License

MIT License. See [LICENSE](LICENSE) for details.
