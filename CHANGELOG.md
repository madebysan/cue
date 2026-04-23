# Changelog

All notable shipped features and changes, organized by date.
Updated every session via `/save-session`.

---

## 2026-04-20 (session 4)

### Distribution
- **Public GitHub repo** at [madebysan/cue](https://github.com/madebysan/cue). Tagged `v0.1.0`, published release with `Cue-0.1.0.dmg` attached. Topics: `macos`, `swift`, `swiftui`, `teleprompter`, `speech-recognition`, `menubar`.
- **Profile listing** — added Cue to the Utilities section of `madebysan/madebysan`.

### Fixes
- **Permission prompts work** — verified mic + speech recognition prompts surface correctly on fresh TCC state. Prior "silent TCC" issue was a cached denial, not a MenuBarExtra vs NSWindow activation issue as first suspected.

### Docs
- **README hero adopted** the standard format: 128px app icon, title, tagline, version line (`Version 0.1.0 · macOS 14+ · Apple Silicon & Intel`), Download link.
- **Removed all references** to Moody and other apps across README, CHANGELOG, and wiki (Home, Getting-Started, Constraints-and-Tradeoffs, Design-Decisions, TranscriptionMatcher).
- **Tightened the tagline** to *"Floating macOS teleprompter. Listens and auto-scrolls your script to match what you say."* — applied to README, repo description, and profile listing.
- **Dropped defensive Status section** and added a Feedback section linking to GitHub Issues.

### Repo hygiene
- Untracked `plan.md`, `backlog.md`, `BUILD_REPORT.md`, `checkpoint.json`, `.v0-mac/prompt.md` from git (they're in `.gitignore` but were committed before that rule was added).

### Status: deployed

---

## 2026-04-21 (session 3)

### Features
- **App icon** — source art rendered to `AppIcon.icns` and wired through `Assets.xcassets/AppIcon.appiconset`. Dock, About panel, and Finder all show the real icon.
- **SwiftUI `MenuBarExtra`** — replaced the `NSStatusItem + NSMenu` approach. Exposes Show/Hide window, live Mic + Speech auth status, Request Permissions, Settings, Quit.
- **About panel credit** — clickable "Made by santiagoalonso.com" in the standard About dialog via `CommandGroup(replacing: .appInfo)`.

### Distribution
- **v0.1.0 signed + notarized + stapled DMG** at `~/Desktop/Cue-0.1.0.dmg` (2.2 MB). Installs as `/Applications/Cue.app`.
- **Apple notarization unblocker** — HTTP 403 was caused by an expired credit card on the Apple Online Store (not the Developer Program agreement, as initially assumed). Clearing the card let `notarytool submit` pass on the first attempt.
- **Signing hardening** — always pass `--entitlements Cue/Cue.entitlements --options runtime` to `codesign`; the `--deep --force` combo without entitlements silently strips sandbox + mic capability.

### Fixes
- **App was being reaped by macOS sudden-termination** when focus bounced to a permission sheet, because a borderless NSPanel reads as "last window closed". Fixed with `applicationShouldTerminateAfterLastWindowClosed = false` + `ProcessInfo.processInfo.disableSuddenTermination()`.
- **DMG volname clash** — stale `diskarbitrationd` entries for previous "Cue" / "Install Cue" volumes caused `hdiutil create "Operation not permitted"`. Using volname `Cue Installer` sidesteps it.

### Known issue (deferred to next session)
- **Permission prompts not appearing.** `AVCaptureDevice.requestAccess(for: .audio)` and `SFSpeechRecognizer.requestAuthorization(...)` fire from inside the SwiftUI `MenuBarExtra` Button closures (confirmed in `app.log`), but the macOS system dialog never surfaces. Teleprompter core flow (mic → speech → scroll) stays dark until this is resolved. Diagnosis to continue post-restart.

### Status: v0.1.0 DMG signed/notarized locally; installed build cannot be granted mic/speech permissions — core feature non-functional in production build until permission prompt issue is solved

---

## 2026-04-20 (session 2)

### Renames
- **Named the app Cue.** Tagline: *Practice on Cue.* Bundle ID `com.san.Cue`. Swift source, `project.yml`, entitlements, all docs, and the wiki were swept to match.

### Features
- **Permission-denied UI hint** — when the user has denied mic or speech recognition, the app now shows an inline overlay explaining how to re-enable it in System Settings instead of silently failing.

### Fixes
- **Logger moved to `~/Library/Logs/Cue/app.log`** and wrapped entirely in `#if DEBUG` so Release builds write nothing to disk.
- **Sandbox re-enabled** (`com.apple.security.app-sandbox = true`). Debug + Release builds both verified via `codesign -d --entitlements`.
- **`--qa-visible` launch flag gated behind `#if DEBUG`.** Release binaries always have `sharingType = .none` — the privacy feature is no longer defeatable in shipped builds.
- **Opacity slider minimum raised from 0.3 → 0.5** to prevent unreadable text-on-background contrast.

### Cleanup
- Deleted `Cue/Services/ScrollController.swift` (dead since the transcription switch).
- Deleted `Cue/Views/VolumeMeterView.swift` (dead since the UI simplification).
- Removed `SpeechTranscriber.append(buffer: AVAudioPCMBuffer)` legacy method — only `append(sampleBuffer:)` remains.
- `.gitignore` extended to exclude local tracking files from any future public repo.

### Docs
- `LICENSE` (MIT) added.
- `README.md` footer rewritten to standard format (`## License` → `[MIT](LICENSE)` → `---` → `Made by santiagoalonso.com`).
- `backlog.md` updated with ship-checklist audit results + completed-today log.

### Status: committed, sandbox + DEBUG-gated debug surfaces ready, notarization blocked on Apple agreement, app icon still placeholder

---

## 2026-04-19 (session 1)

### Features

- **v0-mac skill build** — scaffolded the project via the new `/v0-mac` skill (xcodegen + SwiftUI + AppKit). Initial 11-feature v0 shipped per `plan.md`: floating window, invisible to screenshots, spacebar toggle, countdown, speed slider, volume meter (later removed).
- **Transcription-based scroll** — replaced the RMS-threshold voice model with real speech recognition. Uses Apple's `SFSpeechRecognizer` + on-device where supported. Partial results stream into a `TranscriptionMatcher` that fuzzy-matches recent words against a rolling lookahead window in the script.
- **Fuzzy matcher** — Levenshtein-based per-word similarity + multi-word phrase matching. Never backtracks, tolerates mispronunciation, handles skipped lines by jumping forward, ignores off-script talk by holding position.
- **NSTextView-backed teleprompter surface** — replaces SwiftUI `TextEditor` so we can auto-scroll to an exact character offset (the matched position from the transcription).
- **Notch-style floating UI** — borderless panel pinned to top-center of the screen. Sharp top corners, rounded bottom corners, dark semi-transparent background. Remembers size/position between launches via `setFrameAutosaveName`.
- **Unified play action** — removed the separate mic toggle. Play starts mic + speech + scroll; pause stops everything. One button, one concept.
- **Menu bar status item** — `sparkle` SF Symbol (intentionally not teleprompter-associated). Show/Hide Window, Settings…, Quit.
- **Settings window** — opacity slider (30–100%) and text size default. Accessible via ⌘, or menu bar.
- **Arrow-key manual override** — ↑/↓ nudge the matcher position ±5 words.
- **File logger** — writes to `~/Desktop/cue-log.txt` for debugging (truncated each launch).

### Fixes

- **macOS 26 AVAudioEngine tap silence** — AVAudioEngine's `installTap(onBus:)` callback never fires on macOS 26 in some configurations (especially Bluetooth mics / AirPods). Workaround: abandon AVAudioEngine entirely and use `AVCaptureSession` + `AVCaptureAudioDataOutput`, feeding `CMSampleBuffer`s directly to `SFSpeechAudioBufferRecognitionRequest.appendAudioSampleBuffer`.
- **SwiftUI Button concurrency crash** — Button taps on `@MainActor`-annotated `ObservableObject` classes triggered `MainActor.assumeIsolated` → null deref on macOS 26. Removed `@MainActor` from all service classes; dispatch `@Published` updates via `DispatchQueue.main.async` instead.
- **Mic not starting at launch when voiceMode was remembered ON** — `@AppStorage` restores the saved state but `.onChange` only fires on *change*. Added explicit `.onAppear` start if voiceMode was true (later removed when mic toggle was eliminated).
- **TeleprompterView scroll loop** — every partial recognition result re-rendered the view and kicked off a new animator, causing layout loops. Now only scrolls when offset actually changes; uses direct `setBoundsOrigin` (no animator).
- **Double start on AVAudioEngine restart** — AVAudioEngine can't reliably be stopped and started on the same instance. Recreated the engine on every start. (Later dropped entirely.)
- **Reset button defensive flow** — stops speech + scroll first, clears countdown, then resets the matcher. Prevents reset-while-scrolling layout conflicts.
- **Perf: removed `@Published` from per-sample mic fields** — `level`, `sampleCount`, `lastRawRMS` were driving ~60 Hz SwiftUI re-renders for nothing after the volume meter was removed.

### Data

- **Placeholder script** — replaced the short default with a ~750-word self-documenting test script that walks the user through cadence changes, off-script improv, and skip-ahead scenarios.

### Docs

- `plan.md` — original v0-mac spec
- `plan-dumb.md` — kept as a reference for the alternative simpler version
- `BUILD_REPORT.md` — from the initial autonomous ralph-loop build
- `backlog.md` — comprehensive open work: testing scenarios, coexistence with Zoom/Meet, full-screen-share invisibility verification, v2 features (TOC/jumps, hover-to-pause, mirror mode, multi-script library)
- `README.md` — created

### Status: committed, not deployed, known crash on second play-press under investigation
