# Design Decisions

ADR-style log of significant choices. Each entry captures what was decided, what was considered, and what the evidence is in the code. Written during the v0 build session 2026-04-19 — these were all live decisions, not post-hoc rationalizations.

---

## DD-001: Use AVCaptureSession for mic input, not AVAudioEngine

**Context:** Every Swift teleprompter tutorial uses `AVAudioEngine` + `inputNode.installTap(onBus:)`. That was the obvious first choice.

**Decision:** Use `AVCaptureSession` + `AVCaptureAudioDataOutput` as the mic source. Drop AVAudioEngine entirely.

**Rationale:** On macOS 26, AVAudioEngine's input tap callback **never fires** with Bluetooth microphones (tested with AirPods Pro 3). `engine.start()` succeeds, the tap is "installed", but zero audio buffers ever arrive. No error, no crash, just silence. No amount of connecting the inputNode to a mainMixer, calling `prepare()`, or recreating the engine on every start fixes it.

Testing in parallel showed `AVCaptureSession` reliably delivers audio on the same hardware. It's the API used by QuickTime, Zoom, and the CoreMedia-based apps — and it has three additional benefits:

1. **Non-exclusive access** — multiple apps can capture mic simultaneously (we need to coexist with Zoom/Meet)
2. **Triggers the orange mic-in-menu-bar indicator** reliably
3. **Delivers `CMSampleBuffer`s that `SFSpeechRecognizer` accepts directly** via `appendAudioSampleBuffer` — no AVAudioPCMBuffer conversion needed

**Alternatives considered:**

- Stick with AVAudioEngine and add `AVCaptureSession` alongside "just to wake the mic hardware" — worked briefly but still crashed on mic toggle cycles
- Use TypeWhisper's approach (AVAudioEngine with custom recovery) — their crash reports on macOS 26 show they have the same bug unresolved
- Abandon speech recognition and use the HAL directly — overkill

**Consequences:**

- ✅ Rock-solid audio capture on macOS 26 + AirPods
- ✅ Non-exclusive — works during Zoom calls
- ✅ One less framework to keep alive
- ⚠️ Slightly different latency characteristics than AVAudioEngine (not measured; no UX impact observed)

**Evidence:**
- `Cue/Services/MicLevelMonitor.swift` — entire file
- `~/.claude/decisions.md` — the macOS & iOS section has the full writeup as a reusable insight

---

## DD-002: Rolling fuzzy lookahead matcher, not full-alignment

**Context:** The matcher's job is to map streaming recognized speech back to a position in a ~1,000-word script. Known algorithms: Needleman-Wunsch, Smith-Waterman, BK-tree, vector embeddings.

**Decision:** Custom rolling fuzzy lookahead with Levenshtein per-word similarity + multi-word phrase matching. No alignment DP, no embeddings, no ML.

**Rationale:**

- **Streaming, not batch.** The full-alignment algorithms assume you have both strings complete. We have a fixed script but the recognized text grows over time. Re-running alignment on every partial result would be O(N²) per update.
- **Forward-only is a feature, not a limitation.** For a teleprompter, never going backwards is exactly the right semantics. A matcher that jumps around would be unusable. Lookahead naturally enforces this.
- **Common words don't cause false jumps.** Multi-word phrase matching ("the quick" instead of "the") kills the main failure mode.
- **Fuzzy tolerance is achievable with a 20-line Levenshtein.** No library needed.

**Alternatives considered:**

- **Full Needleman-Wunsch alignment on every partial.** Correct but expensive. Would work for scripts under a few hundred words but scales badly.
- **Vector embeddings with sliding window.** Overkill for word-level matching; adds a dependency on an embedding model.
- **SFSpeech's built-in word timestamps + linear scan.** Might work but makes the matcher speech-provider-specific.

**Consequences:**

- ✅ Fast — O(lookAhead × phraseSize × wordLen²) per recognition callback, trivial
- ✅ Tolerates improvisation (off-script talk = no match = hold position)
- ✅ Portable — pure Swift, no dependencies
- ⚠️ First-phrase latency — takes 2–3 words of speech before a match fires, because we need the phrase needle
- ⚠️ Can't handle true backtracking (user re-reads a passage) — by design

**Evidence:** `Cue/Services/TranscriptionMatcher.swift`

---

## DD-003: Use server-based speech recognition, not on-device

**Context:** Apple's `SFSpeechRecognizer` supports both modes via `requiresOnDeviceRecognition`. Privacy-sensitive apps (medical, legal) use on-device. Transcription-heavy apps use server.

**Decision:** `requiresOnDeviceRecognition = false` (server mode) for now.

**Rationale:** During development, on-device recognition occasionally stalled — emitted the first partial result, then nothing. Server mode was consistently responsive. Our use case doesn't have special privacy requirements (the user is reading a script they wrote), so server mode is acceptable.

**Alternatives considered:**

- On-device — preferred for privacy and offline use, but flaky during testing
- Dynamic switching based on network availability — too complex for v0

**Consequences:**

- ✅ Reliable live partial results
- ⚠️ Requires network
- ⚠️ Audio leaves the device (still end-to-end encrypted, but not on-device)
- 🔧 Easy to flip later — one line change + SettingsView toggle

**Evidence:** `Cue/Services/SpeechTranscriber.swift` — `req.requiresOnDeviceRecognition = false`

---

## DD-004: Use NSTextView via NSViewRepresentable, not SwiftUI TextEditor

**Context:** The whole value prop requires scrolling to an exact character position in the script. SwiftUI's `TextEditor` doesn't expose layout-manager-level information.

**Decision:** Wrap `NSTextView` + `NSScrollView` in an `NSViewRepresentable` called `TeleprompterView`. Use `NSLayoutManager.boundingRect(forGlyphRange:in:)` to compute scroll target.

**Rationale:** No SwiftUI-native way to say "scroll so character at index N is visible". `ScrollViewReader.scrollTo(_:)` only accepts view IDs, not character offsets — you'd need to render one `Text` per token and assign each an ID, which would cripple rendering for anything over ~500 tokens.

`NSTextView` gives pixel-precise character targeting, maintains edit/undo/cursor state natively, and is what Apple's own text surfaces (Pages, Notes) use.

**Alternatives considered:**

- SwiftUI `ScrollViewReader` with token-per-Text layout — dies at large scripts
- Hand-built `Canvas` with manual glyph layout — way too much work
- Render markdown with WKWebView and use JS for scroll targeting — adds a WebKit dependency for no reason

**Consequences:**

- ✅ Pixel-accurate scroll targeting
- ✅ Native text editing/undo/cursor behavior
- ✅ Handles long scripts efficiently (NSTextView is designed for it)
- ⚠️ Re-introduces AppKit idioms inside SwiftUI — small mental load
- ⚠️ `@Binding<String>` two-way sync requires a Coordinator

**Evidence:** `Cue/Views/TeleprompterView.swift`

---

## DD-005: Strip @Published from per-sample fields

**Context:** `MicLevelMonitor` and `SpeechTranscriber` started with lots of `@Published` properties (level, RMS, buffer count, etc.) so they could drive live UI (volume meter, diagnostic row). After the UI simplified to just a play button, nothing in the view body consumed those values — but they were still firing 60 times per second.

**Decision:** Keep `@Published` only on fields actually read inside `ContentView.body`. Demote everything else to plain `var`.

**Rationale:** A `@Published` update on a `@StateObject` forces SwiftUI to re-evaluate `body`. If `body` doesn't depend on that field, the diff pass is wasted — but at 60 Hz from the audio thread, that waste adds up. Stripping `@Published` eliminates the pointless re-renders entirely.

Only kept `@Published`: `isRunning`, `permissionDenied`, `authStatus`, `currentWordIndex`, `currentCharOffset`, `totalTokens`. Everything else is plain.

**Consequences:**

- ✅ Significantly fewer wasted SwiftUI diff passes per second
- ✅ Lower CPU baseline during a session
- ⚠️ If we re-add a live volume meter, we'll need to re-add `@Published` to `level` (cheap and obvious)

**Evidence:** `Cue/Services/MicLevelMonitor.swift`, `Cue/Services/SpeechTranscriber.swift` — comments in each explain which are observed vs plain

---

## DD-006: Kill the mic toggle — unify Play

**Context:** The first UX had a separate mic toggle (🎤 / 🎤/) next to the play button. Users had to turn the mic on, then press play. Inverting the order (press play without mic on) didn't work at first.

**Decision:** Remove the mic toggle entirely. Play = start mic + speech + scroll. Pause = stop everything.

**Rationale:** The mic being on without play doing anything is a dead state. The mic being off when play is pressed is an error state. Both are eliminated by tying them together. One button, one concept: "start reading".

The fallback-speed slider for "manual mode when speech isn't available" remains in the codebase but is hidden — it only appears if speech permission is denied.

**Alternatives considered:**

- Keep the toggle as "advanced mode" — adds a state for zero value
- Make the play button double as a mic toggle (long-press) — too clever
- Auto-start mic on app launch — creates the orange dot before the user has done anything, feels intrusive

**Consequences:**

- ✅ Simpler mental model
- ✅ Less state to get wrong
- ⚠️ Users can't preview the volume meter before pressing play — acceptable given the meter isn't currently shown anyway

**Evidence:** `Cue/ContentView.swift` — `controlBar` has no mic toggle, `togglePlay` handles the full lifecycle

---

## DD-007: No @MainActor on service classes

**Context:** Default-isolation for Swift Concurrency would make all `ObservableObject` classes `@MainActor`. That's recommended for SwiftUI compatibility.

**Decision:** Services are **not** `@MainActor`. State is updated via explicit `DispatchQueue.main.async` from background threads.

**Rationale:** On macOS 26, SwiftUI `Button` actions that touch `@MainActor ObservableObject` trigger a crash inside `_ButtonGesture.internalBody` → `MainActor.assumeIsolated` → null deref. The crash happens BEFORE the action closure runs. Reproduced reliably during development.

Removing `@MainActor` fixes the crash. We lose compile-time enforcement of main-thread state mutation, but `DispatchQueue.main.async` at all write sites is a reasonable substitute until Apple fixes the bug.

**Alternatives considered:**

- Keep `@MainActor` and wrap button actions in explicit `Task { @MainActor in ... }` — didn't reliably fix it
- Disable Swift Concurrency strict checking — nuclear option, still doesn't fix runtime behavior
- Use `.onTapGesture` instead of `Button` to bypass `_ButtonGesture` — works but loses keyboard/accessibility support

**Consequences:**

- ✅ No button-tap crashes
- ⚠️ Developer must remember to bounce to main queue manually on writes
- 🔧 Revisit after macOS 27 — likely fixed

**Evidence:** `Cue/Services/*.swift` — none of them have `@MainActor`. `DispatchQueue.main.async` is used inside capture callbacks.

---

## DD-008: Notch-style window shape

**Context:** The app needs to sit near the camera so the user's eyes appear to look at the lens. The signature look is a window that appears to extend from the MacBook notch.

**Decision:** Borderless `NSPanel` pinned to top-center of the screen, sharp top corners + rounded bottom corners, dark semi-transparent background. Default 380×100.

**Rationale:**

- **Borderless** removes the title bar and traffic lights — nothing to break the visual flow from the notch
- **Sharp top corners** let the window's top edge touch the screen edge cleanly
- **Rounded bottom corners** make it look intentional, not like a stuck dropdown
- **Pinned to top-center** positions it just below the notch on notched MacBooks, at the top edge on others
- **Compact size** — the whole point is to minimize eye movement. 380px wide × 100px tall fits 2–3 lines of 18pt text.

**Alternatives considered:**

- Full titled window with rounded corners — the notch-extending look isn't possible
- Fully transparent with no background — text is unreadable over camera feeds
- Menu bar dropdown — too small for a teleprompter

**Consequences:**

- ✅ Notch-extending aesthetic
- ✅ Minimizes eye movement while reading
- ⚠️ No traffic lights means no visible way to close — mitigated by an `✕` button in the control bar + Cmd+Q + menu bar Quit
- ⚠️ Size is remembered, but on a different screen the position might end up off-screen — `setFrameAutosaveName` handles this on reconnect

**Evidence:** `Cue/AppDelegate.swift` — `applicationDidFinishLaunching`; `Cue/ContentView.swift` — `UnevenRoundedRectangle` background

---

## DD-009: Disable sandbox during development

**Context:** The app was originally shipped with sandbox on. Adding a file logger to `~/Library/Logs/Cue/app.log` required either (a) `com.apple.security.files.user-selected.read-write` with a user prompt, (b) a temporary exception entitlement for the Desktop path, or (c) turning sandbox off.

**Decision:** Sandbox OFF during development. Must be re-enabled before shipping.

**Rationale:** Fastest path to readable logs during iteration. The app is running locally on the developer's machine, not distributed. Security implications are nil.

**Alternatives considered:**

- Write logs to the sandboxed container (`~/Library/Containers/com.san.Cue/Data/...`) — works but user has to dig through Finder to read them
- Use `os.log` and `log show` from Terminal — works but can't be tailed by a Cursor/VS Code extension

**Consequences:**

- ✅ Easy debugging during development
- ⚠️ Must re-enable before ship. Tracked in `backlog.md`.
- ⚠️ `Cue/Cue.entitlements` has `com.apple.security.app-sandbox` set to `false` with a comment explaining why

**Evidence:** `Cue/Cue.entitlements`

---

## Related

- [Architecture](Architecture.md) — how these decisions manifest in the runtime graph
- [Constraints and Tradeoffs](Constraints-and-Tradeoffs.md) — what these decisions cost us
- [Troubleshooting](Troubleshooting.md) — diagnostics for the macOS 26 audio bugs
- `~/.claude/decisions.md` (outside the repo) — macOS insights from this project that apply to other macOS apps
