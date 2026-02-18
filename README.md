# Conversation Assistant

A real-time voice conversation assistant for macOS that listens, transcribes, and responds using a **VAD + Whisper + Claude** pipeline. Built entirely in Swift with no third-party dependencies.

Conversation Assistant captures audio through Voice Activity Detection (Silero VAD on CoreML), transcribes speech via Groq Whisper at 216x realtime, classifies speakers, and streams intelligent responses from Claude Haiku 4.5 — all with sub-second latency.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        macOS Audio Input                             │
│                    (Microphone / System Audio)                        │
└──────────────────────┬───────────────────────────────────────────────┘
                       │ 16kHz mono PCM
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                   Voice Activity Detection (VAD)                     │
│                                                                      │
│  ┌─────────────────────────┐   ┌──────────────────────────────────┐  │
│  │    Silero VAD (CoreML)  │   │  Adaptive Threshold (Fallback)   │  │
│  │  LSTM · 576-sample      │   │  dB-based · rolling baseline     │  │
│  │  chunks · 87.7% acc     │   │  18dB onset · 10dB offset        │  │
│  └─────────────────────────┘   └──────────────────────────────────┘  │
│                                                                      │
│  Speech threshold: 0.5 │ Silence timeout: 650ms │ Min duration: 500ms│
└──────────────────────┬───────────────────────────────────────────────┘
                       │ Speech segments (audio data)
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Speech-to-Text (Whisper)                           │
│                                                                      │
│  ┌─────────────────────────┐   ┌──────────────────────────────────┐  │
│  │   Groq Whisper API      │   │   Deepgram Streaming (Optional)  │  │
│  │   whisper-large-v3-     │   │   Real-time streaming STT        │  │
│  │   turbo · 216x realtime │   │   Configurable via AppSettings   │  │
│  └─────────────────────────┘   └──────────────────────────────────┘  │
└──────────────────────┬───────────────────────────────────────────────┘
                       │ Transcribed text
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                   Claude Haiku 4.5 (Anthropic)                       │
│                                                                      │
│  • Streaming responses via SSE          • Multi-turn conversation    │
│  • Speaker classification               • Up to 20 message pairs    │
│  • Image analysis (base64 PNG)          • Retry with exp. backoff   │
│  • Connection warmup during STT         • 4096 max output tokens    │
└──────────────────────┬───────────────────────────────────────────────┘
                       │ Streamed response
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      Presentation Layer                              │
│                                                                      │
│  Timeline ──── Markdown rendering, syntax highlighting               │
│  Notes ─────── Searchable knowledge base with ⌘F                    │
│  Coding ────── Screenshot capture + AI code analysis                 │
│  Voice ─────── Live transcription + conversation view                │
└──────────────────────────────────────────────────────────────────────┘
```

### Pipeline latency breakdown

| Stage | Typical latency |
|-------|----------------|
| VAD detection | ~36ms per chunk (real-time) |
| Silence → segment ready | 650ms after speech ends |
| Groq Whisper transcription | ~50ms for 10s of audio (216x realtime) |
| Claude first token (streamed) | ~200–400ms |
| **End-to-end** | **~1–1.5s from speech end to first response token** |

---

## Features

- **Real-time voice pipeline** — VAD detects speech, Whisper transcribes, Claude responds, all streaming
- **Silero VAD on CoreML** — On-device LSTM model with 87.7% accuracy, no cloud dependency for detection
- **Sub-second transcription** — Groq Whisper runs at 216x realtime
- **Speaker classification** — Distinguishes interviewer vs. interviewee in conversation context
- **Screenshot + code analysis** — Capture screen, analyze code with Claude (Problem Solving / Code Review modes)
- **Tool integrations** — Jira, Confluence, GitHub, and web search with parallel execution and retries
- **Privacy-first** — Notes stored locally, screen-share invisible window, no telemetry
- **Keyboard-driven** — Full workflow without touching the mouse

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘L` | Hide / show window |
| `⌘1` `⌘2` `⌘3` | Switch tabs (Notes, Coding, Voice) |
| `⌘S` | Capture screenshot |
| `⌘Enter` | Analyze with AI |
| `⌘F` | Search notes |
| `⌘M` | Toggle analysis mode |
| `⌘G` | Clear session |
| `⌘←→↑↓` | Move window |

---

## Project Structure

```
conversation-assistant/
├── conversation_assistant.swift    # App entry point, UI framework, window management (7k lines)
├── Domain/
│   ├── Entities/                   # ConversationMessage, CodingSession, AppSettings
│   ├── Model/                      # AnalysisMode, DataSourceConfig, Tab
│   └── ValueObjects/               # SessionId, ApiKey, CodeBlock
├── Application/
│   └── UseCases/                   # ConfigureApiKey, CaptureScreenshot, AnalyzeCodingTask
├── Infrastructure/
│   ├── Speech/                     # SileroVADRecorder, VADAudioRecorder, GroqWhisperClient,
│   │                               # DeepgramStreamingClient, SystemAudioCapture
│   ├── API/                        # AnthropicApiClient (streaming), AnthropicClient, OpenAIClient
│   ├── Auth/                       # OAuthManager, ApiKeyManager, KeychainApiKeyStore
│   ├── Capture/                    # ScreenCaptureService, MacScreenCapture
│   ├── Tools/                      # ToolExecutor, Jira/Confluence/GitHub/WebSearch clients
│   └── Storage/                    # QADatabase
├── Presentation/
│   ├── Timeline/                   # MessageViewFactory, StreamingMessageHandler
│   ├── Windows/                    # ScreenshotAlertWindow, WindowFactory
│   ├── Settings/                   # SettingsWindowController
│   ├── Styling/                    # MarkdownRenderer, SyntaxHighlighter
│   └── Onboarding/                 # Permissions, Atlassian OAuth onboarding
├── Resources/                      # Assets
├── SileroVAD.mlmodelc/            # CoreML voice activity detection model
├── Tests/
├── build.sh                        # Dev build
├── build-release.sh                # Signed release build
├── create-dmg.sh                   # DMG packaging
└── notarize.sh                     # Apple notarization
```

---

## Requirements

- **macOS 14.0** (Sonoma) or later
- **API keys**: Anthropic (required), Groq (for Whisper STT), optionally Deepgram
- No third-party Swift packages — pure native frameworks (Cocoa, AVFoundation, CoreML, ScreenCaptureKit)

## Getting Started

```bash
# Clone and build
git clone <repo-url>
cd conversation-assistant
./build.sh

# Run
./build/ConversationAssistant.app/Contents/MacOS/ConversationAssistant
```

On first launch, open Settings to configure your API keys (Anthropic, Groq). Grant Screen Recording and Microphone permissions when prompted.

## Building for Distribution

```bash
# Build, package, and notarize (requires Apple Developer ID)
./build-release.sh && ./create-dmg.sh && ./notarize.sh
```

See [README-RELEASE.md](README-RELEASE.md) for the full signing and notarization guide.

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift (100% native, no SPM dependencies) |
| UI | Cocoa (NSView / NSViewController) |
| Architecture | Clean Architecture (Domain → Application → Infrastructure → Presentation) |
| VAD | Silero VAD via CoreML |
| Speech-to-Text | Groq Whisper (`whisper-large-v3-turbo`) |
| LLM | Claude Haiku 4.5 (`claude-haiku-4-5-20251001`) |
| Audio | AVFoundation (16kHz mono PCM capture) |
| Screen Capture | ScreenCaptureKit |
| Auth | Keychain (API keys), OAuth 2.0 (Atlassian) |

---

## License

All rights reserved. See [PRIVACY_POLICY.md](PRIVACY_POLICY.md) for data handling details.
