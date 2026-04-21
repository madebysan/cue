# Getting Started

## Prerequisites

- macOS 14 (Sonoma) or later. Developed and tested on macOS 26.3
- Xcode 26 (installed)
- Homebrew + `xcodegen`: `brew install xcodegen`
- Microphone access — granted when the app first asks
- Speech Recognition access — granted when the app first asks
- **Siri & Dictation must be enabled** in System Settings → Apple Intelligence & Siri (or equivalent). Without this, `SFSpeechRecognizer.isAvailable` returns false.

## First Run

```bash
cd ~/Projects/cue

# Generate the Xcode project from project.yml (only needed after editing project.yml)
/opt/homebrew/bin/xcodegen generate

# Build for macOS
xcodebuild \
  -project Cue.xcodeproj \
  -scheme Cue \
  -destination 'platform=macOS' \
  build

# Launch
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Cue.app" -path "*Debug*" | head -1)
open "$APP_PATH"
```

Or open `Cue.xcodeproj` in Xcode and press ⌘R.

On first launch you will get three permission prompts:

1. **Microphone** — required for audio capture
2. **Speech Recognition** — required for transcription
3. (Possibly) a follow-up if Dictation is disabled system-wide

Grant all three. The app stores nothing remotely — all audio processing is on-device where supported.

## Using It

The app opens as a small dark strip pinned to the top-center of your screen (380×100 by default).

1. Click inside the text area and paste your script, then click outside to unfocus
2. Press **Space** or the ▶ button — 3-2-1 countdown appears
3. Start reading — text auto-scrolls to your voice
4. Press **Space** or **Escape** to pause
5. Press **↑ / ↓** to nudge position manually (±5 words)
6. Press **⌘,** for Settings (opacity, text size)
7. Press **⌘Q** to quit

## Resizing and Repositioning

- **Resize:** drag the bottom-right corner. Size is remembered between launches.
- **Move:** drag anywhere on the dark background.
- Default width is narrow (380px) to minimize left-right eye movement while reading.

## Menu Bar

A small ✨ sparkle icon appears in the menu bar. Click for: Show/Hide Window, Settings…, Quit. The icon is deliberately non-obvious — it doesn't scream "teleprompter" to people who glance at your screen.

## Privacy

By default, the window has `sharingType = .none` — it **will not appear** in screen recordings, screen shares (Zoom, Meet, Teams, OBS), or screenshots. This is the signature feature of Cue. Toggling the `--qa-visible` launch argument disables this for diagnostic screenshots only.

```bash
# Launch with the window VISIBLE to screen capture (diagnostic mode)
"$APP_PATH/Contents/MacOS/Cue" --qa-visible
```

## Debug Logs

The debug build writes to `~/Library/Logs/Cue/app.log`, truncated on each launch. Used during development to diagnose the audio/speech pipeline. Will be redirected or disabled before shipping.

## Related

- [Architecture](Architecture.md) — what's actually happening when you press play
- [Troubleshooting](Troubleshooting.md) — fixes for the common macOS 26 audio issues
