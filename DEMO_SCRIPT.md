# Demo Script — LinkedIn Screen Recording

A 60–90 second screen recording that shows the full voice pipeline in action. Record with [Screen Studio](https://www.screen.studio/) or QuickTime at 1920x1080. Keep it tight — no narration pauses, no fumbling. Every second should show something happening.

---

## Pre-recording setup

1. Have the app built and running with API keys configured
2. Prepare a quiet room (VAD needs clean audio to look crisp on camera)
3. Open a coding problem in a browser (e.g., a LeetCode medium) on the left half of the screen
4. Position the Conversation Assistant window on the right half
5. Have the Voice tab active
6. Disable notifications (Do Not Disturb)

---

## Shot list

### Shot 1 — The hook (0:00–0:05)
**What to show:** The app is open, Voice tab active, empty timeline. You start speaking naturally: *"How would you approach a two-sum problem?"*

**Why it matters:** Immediately shows this is a voice-driven tool — no typing, no clicking.

### Shot 2 — VAD + Transcription (0:05–0:12)
**What to show:** The recording indicator pulses while you speak. After you stop, the transcription appears in the timeline within ~1 second.

**What the viewer sees:** Speech detected in real-time, transcribed almost instantly. The speed is the selling point — let the timestamp/latency speak for itself.

### Shot 3 — Claude streams back (0:12–0:25)
**What to show:** Claude's response streams in token-by-token in the timeline. It classifies the question and provides a structured answer with approach, solution outline, and complexity.

**What the viewer sees:** A coherent, formatted answer appearing in real-time. Markdown rendering, syntax highlighting, the whole polish.

### Shot 4 — Follow-up conversation (0:25–0:40)
**What to show:** Ask a follow-up: *"What about the time complexity if we used a brute force approach?"* Let VAD detect it, Whisper transcribe, Claude respond. The multi-turn context is preserved.

**What the viewer sees:** This isn't a one-shot tool — it holds conversation context. The follow-up answer references the previous response.

### Shot 5 — Screenshot + Code analysis (0:40–0:55)
**What to show:** Switch to Coding tab (`⌘2`). Press `⌘S` to capture the coding problem from the browser. Press `⌘Enter`. Claude analyzes the screenshot and streams a code solution with complexity analysis.

**What the viewer sees:** Vision + code analysis working together. Screenshot captured without leaving the app, AI response is immediate and well-formatted.

### Shot 6 — The reveal (0:55–1:05)
**What to show:** Press `⌘L` to hide the window. Show the clean desktop / screen share view — the app is invisible. Press `⌘L` again to bring it back.

**What the viewer sees:** Privacy-first design. Invisible to screen sharing. This is the "oh, interesting" moment.

### Shot 7 — End card (1:05–1:15)
**What to show:** Cut to a static frame with the app name, a one-liner, and a link.

**Text overlay:**
```
Conversation Assistant
VAD + Whisper + Claude · Real-time voice AI · macOS native
github.com/...
```

---

## Recording tips

- **Record at 60fps** — streaming text looks smoother
- **Zoom in on the timeline** when Claude is responding so viewers can read on mobile
- **Use keyboard shortcuts visibly** — show the key press overlay if your recording tool supports it (Screen Studio does)
- **Keep your speech natural** — don't read from a script word-for-word, just know the questions you'll ask
- **One take per shot is fine** — stitch together in post if needed, but continuous is more impressive
- **Audio:** Include your voice but mute system audio (avoid notification sounds)

## LinkedIn post framing

Suggested post text:

> Built a real-time voice assistant that runs entirely on macOS.
>
> The pipeline: Silero VAD (on-device) detects speech, Groq Whisper transcribes at 216x realtime, Claude Haiku streams back answers — all under 1.5 seconds end-to-end.
>
> No Electron. No Python. Pure Swift + CoreML.
>
> [video]

Keep the post technical but accessible. The numbers (216x realtime, 1.5s e2e, 87.7% VAD accuracy) are what make engineers stop scrolling.
