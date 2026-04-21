# Troubleshooting

Diagnostic reference for the macOS 26 audio + speech stack. Written during a painful session of figuring out why nothing worked. Each entry: symptom → root cause → fix.

Before debugging anything else, **read `~/Library/Logs/Cue/app.log`** — the app logs its audio pipeline state every second, including permission status, input format, buffer counts, and recognized text. The log is truncated on each launch so it's always the current session.

---

## App crashes on button tap with no `.ips` crash report

**Symptoms:** App just disappears. No dialog, no sound. Check `~/Library/Logs/DiagnosticReports/` — nothing new.

**Root cause:** SwiftUI layout loop. Typically triggered by:

1. A `@Published` property updating at high frequency during view body evaluation
2. A programmatic scroll (`scrollView.contentView.animator().setBoundsOrigin`) inside `updateNSView`, which triggers another scroll on the next partial result, which triggers another update…
3. An oversized child view (e.g. 140pt text) inside a clipped container (`UnevenRoundedRectangle`) with a `.transition(.opacity.combined(with: .scale))`

**Fix in this codebase:**

- `TeleprompterView` tracks `lastScrolledOffset` in its `Coordinator` and returns early if the offset hasn't actually changed. See [Components/TeleprompterView.md](Components/TeleprompterView.md).
- `updateNSView` uses `setBoundsOrigin` directly (no animator) to avoid in-flight animation conflicts.
- `CountdownView` font reduced from 140pt → 48pt so it fits in the 100px-tall panel.
- `@Published` stripped from per-sample fields (see [DD-005](Design-Decisions.md)).

---

## "No speech detected" error code 1110

**Symptoms:** Press play, read aloud, press pause. Log shows `SFSpeech task error: No speech detected — code=1110`. The scroll never advanced.

**Root cause:** Zero audio buffers reached the recognizer. The SFSpeech task ran for the duration, heard silence, gave up.

**What to check in the log:**

- Search for `speech sample buffer #1 appended` — if missing, no buffers are flowing
- Search for `FIRST SAMPLE` — if missing, `AVCaptureSession` isn't firing its delegate
- Search for `AVCaptureSession started on <device name>` — confirms the session is running

**Common causes:**

1. Mic hardware wasn't actually opened. On macOS 26 with AVAudioEngine, this is common and silent. Use `AVCaptureSession` instead (see [DD-001](Design-Decisions.md)).
2. The `mic.onSampleBuffer` closure isn't wired to `speech.append(sampleBuffer:)`. Check `ContentView.hookUpMicToSpeech()`.
3. The speech recognizer's `request` is nil when `append` is called — either because `start()` was never called or because `stop()` was called between frames.

---

## Mic permission granted but level stays at 0

**Symptoms:** Orange mic dot appears in menu bar (so macOS thinks we have capture), but the app's internal level stays at 0.00.

**Root cause:** Mismatch between what opened the mic and what's trying to read from it.

**Historical: the AVAudioEngine bug.** Earlier versions used `AVAudioEngine.inputNode.installTap(onBus:)`. On macOS 26 with Bluetooth mics, the tap callback silently never fires even though `engine.start()` returns without error. If you're resurrecting any AVAudioEngine code, this is the failure mode.

**Fix:** Already fixed by switching to `AVCaptureSession` (see [DD-001](Design-Decisions.md)).

---

## Button tap crashes inside SwiftUI `_ButtonGesture.internalBody`

**Symptoms:** Click a Button, immediate crash. Stack trace shows:

```
0  libobjc.A.dylib       objc_msgSend + 56
1  libswiftCore.dylib    swift_getObjectType + 204
2  libswift_Concurrency  swift_task_isMainExecutorImpl
5  SwiftUI               MainActor.assumeIsolated
6  SwiftUI               closure #1 in _ButtonGesture.internalBody
```

**Root cause:** SwiftUI `Button` is checking actor isolation before dispatching the action. If the action touches an `@MainActor`-annotated `ObservableObject`, something in Swift concurrency's executor metadata returns null and crashes.

**Fix in this codebase:** No `@MainActor` on `MicLevelMonitor`, `SpeechTranscriber`, `TranscriptionMatcher`, or `ScrollController`. All `@Published` mutations are bounced to main via `DispatchQueue.main.async`. See [DD-007](Design-Decisions.md).

---

## Mic toggle re-prompts permission every rebuild

**Symptoms:** You grant mic permission. Rebuild. Toggle mic on. macOS asks again.

**Root cause:** macOS TCC tracks mic permission by the app's code signature. Ad-hoc signed builds (`CODE_SIGN_IDENTITY: "-"`) produce a new signature on every rebuild, so each build is a new app from TCC's perspective.

**Fix:** Nothing to do during development — it's a consequence of ad-hoc signing. For shipping, a Developer ID signed build keeps the same signature across builds and TCC remembers permissions.

---

## Orange mic indicator appears but recognition returns nothing

**Symptoms:** Orange dot in menu bar, volume meter moves when you speak, but no recognized text in the log, eventually "No speech detected".

**Root cause:** Audio is flowing into the AVCaptureSession, but not into the SFSpeechRecognizer request.

**Check:**

- `speech.append(sampleBuffer:)` is being called (log it)
- `speech.request` is non-nil at the time of append (guard at top of `append`)
- `recognitionTask(with:)` succeeded and returned a non-nil task (log `task = r.recognitionTask(...)` result)

Edge case: If you toggle speech off then on while audio is flowing, there's a window where `request` is nil. The current code returns early silently in that case.

---

## Scroll jumps around unexpectedly

**Symptoms:** The text scrolls to unexpected positions, possibly backwards.

**Root cause:** The matcher is not supposed to do this — it's explicitly forward-only. If you see backwards scrolling, something's wrong.

**Check:**

- Are you programmatically calling `matcher.setCurrentIndex(_:)` with a lower value somewhere? (Used for arrow-key nudges)
- Did the script change (`setScript` was called)? That resets position to 0.
- Is `focusCharOffset` being computed from something other than `matcher.currentCharOffset`?

If none of those apply and you're still seeing backwards motion, there's a matcher bug worth filing.

---

## Typora / another app crashes while Cue is running

**Symptoms:** Some other mic-using app starts crashing around the same time you're testing Cue.

**Root cause:** **Not Cue's fault.** Several macOS 26 mic-using apps (TypeWhisper, possibly others) have an unrelated AVAudioEngine bug. Cue's `AVCaptureSession` is non-exclusive and doesn't affect other apps' mic access. If you're seeing other-app crashes, check their crash reports for `AVAudioEngineImpl::InstallTapOnNode` — that's their bug, not ours.

**Evidence:** `~/Library/Logs/DiagnosticReports/TypeWhisper-*.ips` during our testing showed that exact stack.

---

## Recognition lag feels too long

**Symptoms:** You speak a word, the text scrolls half a second later.

**Root cause:** Normal. SFSpeech in server mode takes 300–800 ms for the first partial, slightly less for subsequent ones. The matcher also waits for a multi-word phrase before advancing.

**Mitigation:**

- Set `requiresOnDeviceRecognition = true` in `SpeechTranscriber` — may be faster on fast Macs
- Reduce `phraseSize` in `TranscriptionMatcher` from 3 to 2 — will advance earlier but risks false matches on common words

Both tracked in `backlog.md` as potential settings.

---

## Window stops appearing after toggling visibility

**Symptoms:** Clicked the menu bar icon → "Show/Hide Window" a few times, now the window is stuck hidden.

**Root cause:** `NSPanel` with `.fullScreenAuxiliary` and `.canJoinAllSpaces` can get into states where `makeKeyAndOrderFront(nil)` doesn't actually show it. Usually a Spaces issue.

**Fix:** Quit (Cmd+Q or menu bar → Quit) and relaunch. The window's position is persisted via `setFrameAutosaveName`, so you won't lose your layout.

---

## Everything works but the app quits "unexpectedly" after a minute

**Symptoms:** Works fine for a bit, then just disappears. No crash dialog.

**Root cause:** Usually the same layout-loop crash described above. Re-check the log — the last line before the silence pinpoints what was in flight when the app died.

---

## Related

- [Design Decisions](Design-Decisions.md) — why the code is structured this way
- [Components/MicLevelMonitor](Components/MicLevelMonitor.md) — audio pipeline details
- [Components/SpeechTranscriber](Components/SpeechTranscriber.md) — recognizer setup
