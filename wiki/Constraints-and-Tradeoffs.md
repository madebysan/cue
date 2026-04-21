# Constraints and Tradeoffs

Honest inventory of what the app can't do, known tech debt, and intentional tradeoffs. Updated as of session 2026-04-19.

## Platform & Version Locks

- **macOS 14 (Sonoma) minimum.** Uses `.onKeyPress`, `UnevenRoundedRectangle`, and `@Observable`-compatible state model — all macOS 14+ APIs.
- **Developed and tested on macOS 26.3 with Xcode 26.** Behavior on intermediate versions (15–25) not verified.
- **Apple Silicon only for all practical purposes.** The binary is arm64. Intel Mac support hasn't been tested.
- **Siri & Dictation must be enabled system-wide** for `SFSpeechRecognizer` to work. This isn't a macOS version constraint — it's a user-setting prerequisite. The app doesn't detect or warn about this at startup; it just silently fails.

## Known Tech Debt

### App icon

Placeholder Xcode icon is still in the binary. Needs replacement before any distribution.

### Apple Developer agreement

Notarization currently fails with HTTP 403 (expired agreement). Needs to be re-accepted at [developer.apple.com](https://developer.apple.com/account).

### `--qa-visible` launch flag

Debug-only flag that disables `sharingType = .none` so screenshots can capture the window. Gated behind `#if DEBUG` — Release builds never honor it, so it's safe in shipped binaries.

## Performance Constraints

### Large scripts may stutter

Every character-offset change calls `lm.ensureLayout(for: tc)` on the visible region and `lm.boundingRect(forGlyphRange:in:)`. For scripts under ~2,000 words this is imperceptible. For 10,000+ word scripts, expect occasional hitches during fast speech.

Mitigation path (v2): paginate the layout, only force-ensure layout around the current position.

### RMS calculation every 10 ms

`MicLevelMonitor.rms(sampleBuffer:)` runs a sum-of-squares loop over ~480 Float32 samples on every capture callback. Loop is trivial but tight. Not optimized; not a hotspot in profiling. If we ever want a high-res volume meter, consider `vDSP.rmsq` from Accelerate for SIMD.

### First recognition lag

SFSpeechRecognizer in server mode takes 300–800 ms to return the first partial result. Combined with the matcher needing 3 words of phrase context, the first scroll happens 2–4 seconds after the user starts reading. Users are accustomed to this from Dictation — but it's not instant.

## Recognition Constraints

### English-only

`SFSpeechRecognizer(locale: Locale(identifier: "en-US"))` is hardcoded. Other languages would be a one-line change to the locale + a setting, but haven't been tested.

### Server-mode requires network

`requiresOnDeviceRecognition = false` is the current choice (see [Design-Decisions.md DD-003](Design-Decisions.md)). On a plane or offline, the recognizer will stall until network returns. No detection or UI feedback for this.

### Recognizer hallucinations

SFSpeech occasionally emits a word that wasn't actually said. The matcher's phrase-match threshold filters these out in most cases, but an unlucky hallucination that happens to match a downstream token could cause a small scroll forward. Not observed in practice.

### Identical-phrase passages confuse the matcher

If the script contains two nearby occurrences of the same 3-word phrase (rare in prose), the matcher will happily jump to the first one in the lookahead window and stay there. Not a practical concern unless you're teleprompting song lyrics with a heavy chorus.

## UI / UX Constraints

### No traffic lights means no visible close affordance

The borderless `NSPanel` has no close button from macOS. Closing requires:

- Cmd+Q
- Click the `✕` in the app's control bar
- Right-click the menu bar sparkle → Quit

First-time users may not immediately see how to close the window — worth revisiting.

### No resize handles

You can resize by dragging the bottom-right corner, but there's no visible grip. Intentional (clean look) but non-obvious.

### `sharingType = .none` + region-screenshot is tricky

During development we couldn't screenshot the window because it's invisible to screen capture. The `--qa-visible` flag exists to work around this. If you need to show someone what the app looks like, launch with the flag.

### `.nonactivatingPanel` was removed

An earlier version used `.nonactivatingPanel` so the app wouldn't steal focus when clicked. That was removed because macOS 26 doesn't route mic audio to non-activating panels — you get the "tap never fires" bug even with AVAudioEngine. Current version activates normally on first interaction.

## Security / Privacy Considerations

- **Mic audio is sent to Apple's speech servers** (server-mode recognition). End-to-end encrypted per Apple's documentation, but not fully on-device. Flip `requiresOnDeviceRecognition = true` if this matters.
- **No script data leaves the device.** Only audio → Apple → recognized text. The script itself is only in memory + UserDefaults.
- **File logger writes to `~/Library/Logs/Cue/app.log`.** Contains recognized text fragments. Anyone with local file access can read it. OK for a dev tool, must be stripped or redirected before ship.
- **`sharingType = .none`** does what it says: the panel is invisible to screencapture, ReplayKit, Zoom/Meet/Teams, OBS. This is the signature privacy feature. Tested manually against Zoom and `screencapture` CLI; not automated.

## Intentional Tradeoffs

- **Simplicity over feature completeness.** Removed the mic toggle, the settings speed slider (unless speech fails), the volume meter. Every removed control was a potential state bug avoided. See [DD-006](Design-Decisions.md).
- **Custom matcher over language model.** A 20-line Levenshtein is fast, auditable, and portable. A neural matcher would be "smarter" but opaque and hard to debug.
- **NSTextView over a custom renderer.** We accept the AppKit-in-SwiftUI seam to get native text editing + layout manager access. Building our own text renderer would be months of work.
- **One script at a time.** No multi-script library in v0. Tracked in `backlog.md`.
- **No undo for scroll position.** If the matcher jumps forward too far, you can only arrow-up to nudge back. No "undo this jump" gesture.

## Related

- [Design Decisions](Design-Decisions.md) — why we accepted these
- [Troubleshooting](Troubleshooting.md) — fixes for the audio / speech failures
- `backlog.md` — what we plan to do about the v2-worthy ones
