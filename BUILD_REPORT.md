# Cue — v0 Build Report

**Built:** 2026-04-19T18:18:00Z
**Iterations:** 1 (one ralph-loop turn)
**Status:** ✅ Complete

## What's Working

- Paste / edit script in the floating panel
- **Spacebar** starts 3-2-1 countdown, then scrolling
- **Spacebar again** or **Esc** pauses
- Adjustable scroll speed slider (20–200 px/sec)
- Adjustable text size slider (14–48 pt)
- Floating window, always-on-top, across all Spaces, above full-screen apps
- **Invisible to screen share and screenshots** (`NSPanel.sharingType = .none`)
- Cmd+drag anywhere to move the window (`isMovableByWindowBackground`)
- Voice-activated mode: when enabled, prompts for mic permission and scrolls only while mic RMS is above the sensitivity threshold (pauses when you pause speaking)
- Live volume meter shows current mic level with a threshold marker
- 3-2-1 countdown overlay with fade + scale transitions
- Settings window (Cmd+,) persists defaults via UserDefaults
- About window (Cmd+Space from app menu) shows clickable "Made by santiagoalonso.com"
- Reset button returns scroll offset to top
- `--qa-visible` launch flag disables screen-capture invisibility for diagnostic screenshots only

All 11 features from plan.md ship in v0. No deferrals.

## How to Run It

```bash
cd /Users/san/Projects/cue

# Regenerate project (only after editing project.yml)
/opt/homebrew/bin/xcodegen generate

# Build
xcodebuild \
  -project Cue.xcodeproj \
  -scheme Cue \
  -destination 'platform=macOS' \
  build

# Launch normally (invisible to screen share)
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Cue.app" -path "*Debug*" | head -1)
open "$APP_PATH"

# Launch with diagnostic visibility (for screenshotting the window)
"$APP_PATH/Contents/MacOS/Cue" --qa-visible

# Or open in Xcode
open Cue.xcodeproj
# Then press ⌘R
```

**macOS target:** 14.0 (Sonoma)
**App shape:** floating_utility (NSPanel)
**Sandbox:** enabled

## Entitlements Granted

- `com.apple.security.app-sandbox` (sandboxed)
- `com.apple.security.device.audio-input` (microphone for voice-activated scrolling + volume meter)

## File Structure

```
cue/
├── project.yml                                  (xcodegen config)
├── plan.md, plan-dumb.md, BUILD_REPORT.md
├── checkpoint.json
├── .v0-mac/
│   ├── prompt.md                                (full ralph-loop task brief)
│   └── screenshots/                             (pass-1, final.png)
└── Cue/
    ├── CueApp.swift                      (@main, About panel)
    ├── AppDelegate.swift                        (NSPanel config)
    ├── ContentView.swift                        (main teleprompter view)
    ├── Cue.entitlements
    ├── Services/
    │   ├── MicLevelMonitor.swift                (AVAudioEngine + RMS)
    │   └── ScrollController.swift               (Timer-based scroll offset)
    └── Views/
        ├── VolumeMeterView.swift
        ├── CountdownView.swift
        └── SettingsView.swift
```

8 Swift files, 541 lines.

## Visual QA

**Passes run:** 1 / 2
**Issues fixed:** 0 P0/P1 (none found)
**Issues deferred to polish:** 0

Screenshots at `.v0-mac/screenshots/`:
- `pass-1/phase3-launch.png` — full screen during launch (Cue's signature invisibility means the window itself doesn't appear in screen capture — this is the feature working, not a failure)
- `pass-1/phase4-qa-visible.png` — launched with `--qa-visible` so the panel is screen-capturable
- `pass-1/window-focused.png` — window-only crop showing control bar and script area
- `final.png` — final state, window-only

## Key Decisions

- **Dropped `Models/ScrollState.swift` enum** — three `@State` vars (`countdown: Int?`, `scroll.isScrolling`, `voiceRunActive`) model the same four states more directly. Per `on_ambiguity: choose_simpler_option`.
- **Used `Timer.scheduledTimer` over `CVDisplayLink`** — CVDisplayLink is deprecated on macOS 15+. Timer at 60Hz is more than smooth enough for text scrolling. Cleaner, no deprecation warnings.
- **`AVAudioEngine` RMS threshold for voice detection (Option B)** — not SFSpeechRecognizer. No privacy-string/speech-permission complexity, no ML overhead. Misfires in noisy rooms are expected and mitigated by the adjustable sensitivity slider.
- **Added `--qa-visible` launch flag** — visual QA cannot screencapture a panel with `sharingType = .none`. The flag toggles `.none` ↔ `.readOnly` for diagnostic builds only. Production users never see the flag. Required for any future visual iteration on this app.
- **Rounded `GENERATE_INFOPLIST_FILE: YES` + INFOPLIST_KEY_\*** instead of a hand-written Info.plist — simpler, modern (Xcode 13+), covers every key we need (copyright credit, mic usage description, min OS).

## Known Issues

- **Voice permission prompt** fires the first time you toggle the microphone on. macOS 14+ routes this through the system sheet. If you deny, `MicLevelMonitor.permissionDenied` is set but there's no UI surfacing yet — v1 could add a hint explaining how to re-enable in System Settings.
- **Large scripts (>5,000 words)** may stutter on the scroll — the whole document is offset in SwiftUI instead of using a paginated approach. Fine for typical teleprompter use (1-2 min scripts). A scroll-view anchor approach would be a v1 improvement.
- **Esc exits full-screen** on macOS before the app's Esc handler runs if Cue happens to be over a full-screen app — the panel's `.fullScreenAuxiliary` behavior interacts with native full-screen. Spacebar is the reliable toggle.

## Next Steps — Recommended

**For v1:**
1. Add a permission-denied UI hint when the user toggles the mic but has previously denied access
2. Persist script text between launches (UserDefaults string or a per-launch .txt file)
3. Paginate the scrolling text for large scripts (only render visible region)
4. Add a global hotkey to toggle window visibility (useful when presenting)
5. Add an optional hover-to-pause mode (Moody has this) — currently you need the keyboard

**Before sharing / distributing:**
- Design an app icon (reference image or programmatic glyph) — add to `Assets.xcassets/AppIcon`
- Run `/release-dmg` to sign with Developer ID, notarize via `notarytool` keychain profile, staple, and package as DMG
- Create a GitHub release with the DMG attached
- Add README.md with a screenshot (use `--qa-visible` to capture)

**If targeting the Mac App Store:**
- Review sandbox entitlements — App Store review will flag the sharingType behavior, so document the privacy-preserving rationale
- Consider removing `--qa-visible` from the shipping binary (or keep it behind a hidden Debug config only)

## Build Stats

- Total Swift files: 8
- Lines of Swift: 541
- Final clean build: **BUILD SUCCEEDED** (no errors, no warnings in Cue target)
- Build configuration: Debug, ad-hoc signed (CODE_SIGN_IDENTITY `-`)

---

*Built with `/v0-mac` — see `~/.claude/skills/v0-mac/` to iterate on the skill itself.*
