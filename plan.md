# Cue — Plan

## Done this session (2026-04-19)
- Scaffolded via `/v0-mac` skill: xcodegen project, sandbox entitlements, floating panel
- Rewrote audio pipeline three times to find what works on macOS 26 — landed on `AVCaptureSession` + `CMSampleBuffer` directly to `SFSpeechRecognizer.appendAudioSampleBuffer`
- Built full transcription-based teleprompter: `SpeechTranscriber` + `TranscriptionMatcher` + NSTextView-backed `TeleprompterView` with programmatic scroll-to-character-offset
- Fuzzy matcher with Levenshtein similarity, rolling lookahead, never-backtracks guarantee
- Unified UX: one play button controls everything (mic + speech + scroll), no more mic toggle
- Notch-style compact floating UI (380×100 default, dark rounded-bottom panel)
- Menu bar status item (sparkle icon — intentionally non-obvious)
- Settings window: opacity slider, text size
- File logger to `~/Desktop/cue-log.txt` for debugging
- Comprehensive `backlog.md` covering testing scenarios, v2 features, housekeeping

## Done this session (2026-04-20)
- Ran `/ship-checklist` audit — all code-side FAIL items knocked out: LICENSE (MIT), README footer standard format, sandbox re-enabled, logger moved to `~/Library/Logs/Cue/app.log` and gated `#if DEBUG`, `--qa-visible` flag gated `#if DEBUG`, `.gitignore` extended.
- Deleted dead code: `ScrollController.swift`, `VolumeMeterView.swift`, `SpeechTranscriber.append(buffer: AVAudioPCMBuffer)`.
- Floored opacity slider at 0.5 (below was unreadable).
- Added inline UI hint when mic or speech permission is denied.
- **Renamed the app MoodyClone → Cue.** Bundle ID now `com.san.Cue`. Tagline: "Practice on Cue." Full rename covers Swift source, project.yml, entitlements, README, wiki, CHANGELOG, backlog.

## Done this session (2026-04-21)
- **App icon** shipped — reference image → `AppIcon.icns` → `Assets.xcassets/AppIcon.appiconset`. Visible in About panel and Dock.
- **Developer ID signed + notarized + stapled DMG** at `~/Desktop/Cue-0.1.0.dmg` (2.2 MB). Root cause of earlier HTTP 403 on notarytool was **not** the Developer agreement — it was the expired credit card on the Apple Online Store. Once that was cleared, notarization succeeded first try.
- **Signing fix:** `codesign --force --deep --sign "Developer ID Application"` without `--entitlements` silently strips them. Now always passes `--entitlements Cue/Cue.entitlements --options runtime` so sandbox + mic capability survive.
- **DMG volname clash:** prior "Cue" and "Install Cue" volumes left stale entries in `diskarbitrationd` → `hdiutil create` returned "Operation not permitted". Worked around with volname `Cue Installer`.
- **Menu bar rethought** — replaced `NSStatusItem + NSMenu` (where weak `target:` made action dispatch unreliable) with SwiftUI `MenuBarExtra { ... }` + `@NSApplicationDelegateAdaptor`. Menu now exposes: Show/Hide, live Mic/Speech status, Request Permissions shortcut, Settings, Quit.
- **Sudden-termination kill** — macOS was reaping Cue whenever focus bounced (e.g. a perm sheet) because a borderless NSPanel registered as "last window closed". Fix: `applicationShouldTerminateAfterLastWindowClosed = false` + `ProcessInfo.processInfo.disableSuddenTermination()`.
- **File Logger survives Release** — during this debug phase the `#if DEBUG` gate was removed so installed DMG builds still write to `~/Library/Logs/Cue/app.log`. Re-gate after the permission mystery is resolved.
- **About panel credit** — clickable "Made by santiagoalonso.com" link wired in `CommandGroup(replacing: .appInfo)`.

## Current state
- **Build:** Debug + Release both pass. Entitlements verified via `codesign -d` against the installed `.app`.
- **Distribution:** signed + notarized + stapled DMG exists, installs to `/Applications/Cue.app`.
- **Runtime:** app launches, menu bar appears, SwiftUI Button closures *do* fire (confirmed in `app.log`: `MenuBar → Mic tapped; status=0`).
- **BLOCKER — permission prompt never appears.** Calling `AVCaptureDevice.requestAccess(for: .audio)` and `SFSpeechRecognizer.requestAuthorization(...)` from the MenuBarExtra Button closures runs the callback path but the macOS system permission dialog does not surface. Without granted permissions, the teleprompter core functionality (mic capture → speech → scroll) is dead. **This is the open problem the next session needs to solve.**

## Next steps (post-restart diagnosis)
- [ ] **Confirm TCC entry** — `tccutil reset Microphone com.san.Cue && tccutil reset SpeechRecognition com.san.Cue`, then quit + relaunch Cue from `/Applications`. A fresh TCC state should force the prompt.
- [ ] **If still silent** — try requesting permissions from a regular `NSWindow`/panel context (e.g. auto-request on `applicationDidFinishLaunching` once) instead of from inside a SwiftUI MenuBarExtra Button closure. Suspicion: the menu-popup NSApplication activation state blocks TCC from showing a prompt.
- [ ] **Inspect unified log while tapping** — `log stream --predicate 'subsystem == "com.apple.tcc"' --info` live while tapping the menu item to see if TCC registers the request at all.
- [ ] **Check bundle identity** — `codesign -d --entitlements - /Applications/Cue.app` to confirm `com.apple.security.device.audio-input` is still present post-install (the DMG staple should not have stripped it, but verify).
- [ ] **Fallback:** if MenuBarExtra closure context is genuinely incompatible with TCC prompts on macOS 26, move permission requests into `applicationDidFinishLaunching` (first-launch only), keep menu items as status indicators + "Open System Settings" deep links.
- [ ] Long-session stress test (10+ min script) — deferred until permissions work.
- [ ] Test coexistence with Zoom/Meet (mic sharing + full-screen-share invisibility) — deferred.
- [ ] Rename project directory `~/Projects/moody-clone/` → `~/Projects/cue/` — still deferred.
- [ ] Re-gate the Release file logger behind `#if DEBUG` after the permission issue is fixed.

## Decisions & context
- **Audio:** AVAudioEngine was abandoned on macOS 26 because its input tap silently never fires with AirPods / certain mic configurations. AVCaptureSession is the only reliable path. It also is non-exclusive so it coexists with Zoom/Meet. See `~/.claude/decisions.md` under macOS for the full write-up.
- **Concurrency:** removed all `@MainActor` annotations from service classes — they caused Button tap crashes on macOS 26 (`MainActor.assumeIsolated` → null deref inside `_ButtonGesture`). Per-thread updates use `DispatchQueue.main.async` instead.
- **Matching:** chose rolling fuzzy lookahead over full alignment (Needleman-Wunsch etc.) because it tolerates improvisation and off-script talk without requiring the user to say the script verbatim.
- **UX simplification:** killed the mic toggle per user request. Play starts everything; pause stops everything. Simpler mental model.

---

# Original v0-mac Plan (historical, for reference)

## Overview
A floating teleprompter app for macOS. Paste a script, press spacebar, the text scrolls automatically. The window floats above every app, stays visible across Spaces and over full-screen apps, and is invisible to screen share and screenshots. Includes simple voice-activated scrolling: when you speak, it scrolls; when you pause, it pauses.

## Tech stack
- **UI:** SwiftUI inside an AppKit `NSPanel` (floating panel, non-activating)
- **Audio:** AVAudioEngine with RMS power detection (no SFSpeechRecognizer — overkill for v0)
- **Persistence:** UserDefaults for speed / text-size / voice-mode-on defaults
- **macOS target:** 14.0 (Sonoma) — matches your current OS
- **Third-party packages:** none

## Features
| # | Feature | Approach | Complexity | Trade-off |
|---|---------|----------|------------|-----------|
| 1 | Paste / edit script | `TextEditor` bound to `@State String` | Low | Standard |
| 2 | Floating always-on-top, multi-Space, over full-screen | `NSPanel` with `.floating` level + `.canJoinAllSpaces` + `.fullScreenAuxiliary` | Low | One-time AppDelegate setup |
| 3 | Invisible in screen share / screenshots | `panel.sharingType = .none` | Low | One API call |
| 4 | Spacebar toggles auto-scroll, Esc pauses | `.onKeyPress(.space)` + `.onKeyPress(.escape)` | Low | Standard SwiftUI |
| 5 | Adjustable speed slider (pixels/sec) | `Slider(value: $speed, in: 20...200)` | Low | Live update during scroll |
| 6 | **Voice-activated mode (toggleable)** | AVAudioEngine RMS → scroll above threshold, pause below. Sensitivity slider. | **Medium — Option B (recommended)** | Misfires in noisy rooms; no speech recognition |
| 7 | 3-2-1 countdown before scroll starts | Overlay with `.transition(.opacity)` | Low | Pure SwiftUI |
| 8 | Cmd+drag anywhere to move window | `panel.isMovableByWindowBackground = true` | Low | Built-in AppKit |
| 9 | Text size adjustment (14-36pt) | `.font(.system(size: textSize))` + slider | Low | Standard |
| 10 | Volume meter bar | Bound to AVAudioEngine level, `Rectangle().frame(width: level * w)` | Low | Already have the level from #6 |
| 11 | About window | System `orderFrontStandardAboutPanel` with "Made by santiagoalonso.com" credit | Low | Required per your CLAUDE.md |

**Option A considered for #6** (speech-to-text via SFSpeechRecognizer to only scroll when actual words detected): rejected for v0. Adds privacy strings, Apple speech permissions, and doesn't materially improve UX over RMS threshold.

## Window / screen inventory
1. **MainPanel** — teleprompter: TextEditor, speed slider, text-size slider, voice toggle, sensitivity slider, volume meter, play/pause indicator, countdown overlay
2. **SettingsWindow** — persistent preferences (defaults for speed/size/voice mode)
3. **AboutWindow** — system About panel with clickable credit

## Entitlements
```xml
com.apple.security.app-sandbox            (sandbox on)
com.apple.security.device.audio-input     (microphone for voice + volume meter)
```
Plus Info.plist: `NSMicrophoneUsageDescription = "Moody listens to your voice to auto-scroll the teleprompter."`

## Window behaviors (AppDelegate)
```swift
panel.styleMask = [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isMovableByWindowBackground = true
panel.titlebarAppearsTransparent = true
panel.sharingType = .none   // invisible in screen share
```

## File structure
```
cue/
├── project.yml
├── Cue/
│   ├── CueApp.swift           # @main
│   ├── AppDelegate.swift             # NSPanel setup
│   ├── ContentView.swift             # MainPanel layout
│   ├── Models/
│   │   └── ScrollState.swift         # enum: idle / counting / scrolling / paused
│   ├── Services/
│   │   ├── MicLevelMonitor.swift     # AVAudioEngine → published Float level
│   │   └── ScrollController.swift    # speed + voice input → scroll offset
│   └── Views/
│       ├── VolumeMeterView.swift
│       ├── CountdownView.swift
│       └── SettingsView.swift
├── Cue/Info.plist
└── Cue/Cue.entitlements
```

## Implementation order
1. Scaffold (xcodegen) + verify sandbox + mic entitlement prompts on first launch
2. Models (ScrollState) and Services (MicLevelMonitor, ScrollController)
3. Views — VolumeMeterView, CountdownView, SettingsView
4. MainPanel ContentView — wire script editor, speed slider, meter, countdown
5. AppDelegate panel config (floating, sharingType, drag, collection behavior)
6. Keyboard handlers (spacebar toggle, Esc pause)
7. About window credit
8. UserDefaults for persistent settings

## run_contract
```yaml
run_contract:
  max_iterations: 30
  completion_promise: "V0_MAC_COMPLETE"
  on_stuck: defer_and_continue
  on_ambiguity: choose_simpler_option
  on_regression: revert_to_last_clean_commit
  human_intervention: never
  macos_target: "14.0"
  app_shape: floating_utility
  sandbox: true
  signing: skip
  visual_qa_max_passes: 2
  phase_skip:
    visual_qa: false
    polish: false
    dmg: true
  entitlements:
    - com.apple.security.device.audio-input
  complexity_overrides:
    voice_activation: "AVAudioEngine RMS threshold (Option B) — not speech recognition"
    window_drag: "isMovableByWindowBackground (built-in)"
    countdown: "SwiftUI .transition(.opacity) animation"
```

## Estimated scope
- ~8-10 Swift files
- ~500-700 lines of Swift
- 20-30 ralph-loop iterations (~30-45 minutes)
