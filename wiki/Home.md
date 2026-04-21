# Cue

**Practice on Cue.**

A floating macOS teleprompter that listens while you rehearse. Apple's on-device speech recognition matches what you say to your script and auto-scrolls to keep your current position visible — pause, improvise, skip ahead, and it adapts. Rehearse out loud, then record eye-to-eye with the camera.

Built for one-person video recording where hiring a teleprompter operator isn't realistic.

## Quick Links

- [Architecture](Architecture.md) — how the pieces fit together
- [Getting Started](Getting-Started.md) — run it
- [Project Structure](Project-Structure.md) — what's in each file
- [Core Concepts](Core-Concepts.md) — terminology and mental model
- [Design Decisions](Design-Decisions.md) — why things are the way they are
- [Constraints & Tradeoffs](Constraints-and-Tradeoffs.md) — known limits
- [Troubleshooting](Troubleshooting.md) — diagnosing the macOS 26 audio stack

## Tech Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| UI | SwiftUI + AppKit | Floating panel, settings, menu bar item |
| Teleprompter surface | NSTextView via NSViewRepresentable | Precise character-offset scrolling |
| Mic capture | `AVCaptureSession` | Reliable, non-exclusive input on macOS 26 |
| Speech | `SFSpeechRecognizer` (on-device) | Live transcription of what you speak |
| Matching | Custom Levenshtein lookahead | Maps recognized words → script position |
| Build | xcodegen → xcodebuild | Reproducible project from `project.yml` |

## Status

**v0 — usable but crash-prone.** Core loop works end-to-end: mic captures, speech transcribes, matcher advances, text scrolls in sync with voice. Known instability under investigation (see `plan.md`). See [CHANGELOG.md](../CHANGELOG.md) for what shipped and [backlog.md](../backlog.md) for what's next.

---

*Last generated: 2026-04-19*
