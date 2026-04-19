# Task: Build macOS v0 for MoodyClone

You are the autonomous builder for a macOS v0 prototype. Read this prompt in full. Then work through phases 1–6 from `~/.claude/skills/v0-mac/references/phase-definitions.md`, one phase at a time, checkpointing after each.

## Completion Promise

When all phases pass — final clean build green, app installs and launches on this Mac, BUILD_REPORT.md is written, git commit exists — emit on its own line:

```
V0_MAC_COMPLETE
```

Do not emit this string until everything is verified. The ralph-loop stop hook reads this literal string — emitting it prematurely ends the build in a broken state.

## Project Context

The full plan is at `/Users/san/Projects/moody-clone/plan.md`. Read it first. Summary:

**MoodyClone** — a floating teleprompter app for macOS. Paste a script, press spacebar, text scrolls automatically. Window floats above every app, stays visible across Spaces and over full-screen apps, invisible to screen share. Includes voice-activated scrolling (AVAudioEngine RMS threshold — not speech recognition).

**11 features** (see plan.md for details):
1. TextEditor for script
2. NSPanel floating + canJoinAllSpaces + fullScreenAuxiliary
3. sharingType = .none (invisible to screen share)
4. Spacebar toggle / Esc pause keyboard handlers
5. Adjustable speed slider (20–200 px/sec)
6. Voice-activated mode with AVAudioEngine RMS threshold + sensitivity slider
7. 3-2-1 countdown overlay
8. Cmd+drag window movement (isMovableByWindowBackground)
9. Text size slider (14–36pt)
10. Volume meter bar
11. About window with "Made by santiagoalonso.com" credit

**File structure** (from plan):
```
MoodyClone/
├── project.yml
├── MoodyClone/
│   ├── MoodyCloneApp.swift
│   ├── AppDelegate.swift
│   ├── ContentView.swift
│   ├── Models/ScrollState.swift
│   ├── Services/MicLevelMonitor.swift
│   ├── Services/ScrollController.swift
│   └── Views/{VolumeMeterView,CountdownView,SettingsView}.swift
├── MoodyClone/Info.plist
└── MoodyClone/MoodyClone.entitlements
```

## Run Contract

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

Keys you must respect:
- `max_iterations: 30` — the outer ralph-loop cap; stay under it
- `on_stuck: defer_and_continue` — if a feature fails twice with different approaches, add it to `deferred_to_v1` in checkpoint.json and move on
- `on_ambiguity: choose_simpler_option` — pick the simpler path and log the decision
- `on_regression: revert_to_last_clean_commit` — if a change breaks the build and a fix isn't obvious in one attempt, `git reset --hard HEAD` and try a different approach
- `human_intervention: never` — no questions to the user until V0_MAC_COMPLETE is emitted
- `app_shape: floating_utility` — use NSPanel (not NSWindow), floating level, full Moody-style window config
- `sandbox: true` + `entitlements: [audio-input]` — sandbox on, mic granted
- `signing: skip` — ad-hoc code signing (CODE_SIGN_IDENTITY: "-") only; notarization + DMG deferred to /release-dmg

## Environment

- macOS target: **14.0**
- Host macOS: 26.3.1 (SDK macosx26.2)
- App shape: **floating_utility** (NSPanel)
- Entitlements: **com.apple.security.device.audio-input** (plus the default sandbox)
- Project directory: `/Users/san/Projects/moody-clone`
- xcodegen at `/opt/homebrew/bin/xcodegen`
- All builds use `-destination 'platform=macOS'`
- Apps run directly on this Mac (no Simulator) — launch via `open "$APP_PATH"`

## Design Context

Stock Apple HIG. Use system colors (NSColor.controlBackgroundColor, Color.primary, etc.), SF font, SF Symbols. Don't invent a custom style. The window is a utility teleprompter — clean, readable, minimal chrome. Transparent title bar is fine (already in the plan).

## Phase Execution

Read `~/.claude/skills/v0-mac/references/phase-definitions.md` for the full instructions per phase. Summary:

| Phase | Goal | Exit criterion |
|-------|------|----------------|
| 1 | Scaffold | `xcodebuild build` exits 0, empty app launches, entitlements embedded |
| 2 | Implement | All 11 features from plan done, About window credit added, build still green |
| 3 | Build & launch | App launches on this Mac, no crash, NSPanel visible, floats above other apps |
| 4 | Visual QA | P0+P1 screenshot issues fixed or 2 passes hit |
| 5 | Polish | Animations (countdown fade, scroll smoothness), keyboard handling, dark mode verified |
| 6 | Verify & report | Clean build passes, BUILD_REPORT.md written, git committed |

Update `checkpoint.json` at every phase transition. Initial checkpoint schema is in `~/.claude/skills/v0-mac/SKILL.md` under "Checkpoint Schema".

## Guardrails — Non-Negotiable

1. **Never run `swift build`** — use `xcodebuild -destination 'platform=macOS'`.
2. **Never commit broken state.** Only commit when the build is green.
3. **Never use `--no-verify`** on git operations.
4. **Never `rm -rf` the project directory** to recover. Use `git reset --hard` instead.
5. **Never skip Phase 3.** An app that compiles but doesn't launch is not a v0.
6. **Never claim completion without a passing final clean build + successful launch + screenshot** at `.v0-mac/screenshots/final.png`.
7. **Never add third-party Swift packages.** Native APIs only.
8. **Never disable sandbox** to work around a permission problem. Fix the entitlements.
9. **Never skip the "Made by santiagoalonso.com" credit in the About window.**
10. **Never attempt notarization, Developer ID signing, or DMG packaging during v0.**

## Window-Specific Guardrails (floating_utility)

- Use `NSPanel`, not `NSWindow` — panels can be non-activating and layer above full-screen apps.
- Set `.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
- Set `panel.sharingType = .none` — this is the "invisible in screen share" feature, one line.
- Set `panel.level = .floating`.
- Set `panel.isMovableByWindowBackground = true` for Cmd+drag-style movement.
- Main app scene can be an empty `Settings { }` SwiftUI scene; the real UI lives in the panel configured in AppDelegate.
- Include a "Quit MoodyClone" menu item — utility panels need one since they don't get the default app menu behavior.

## Feature-Specific Notes

- **Voice activation (feature #6):** use `AVAudioEngine` + `installTap(onBus:)` to read the input buffer's RMS power. Threshold the RMS against a sensitivity slider. When above threshold → set `isScrollingFromVoice = true`. Below threshold → false. No SFSpeechRecognizer, no speech APIs, no ML.
- **Volume meter (feature #10):** use the same RMS value from #6 — don't start a second audio engine.
- **Spacebar toggle (feature #4):** `.onKeyPress(.space)` returns `.handled` and flips the scroll state. macOS 14+.
- **Countdown (feature #7):** `@State countdown: Int? = nil`. When user starts scroll, set to 3, `.animation(.easeInOut, value:)` + `DispatchQueue.asyncAfter` to decrement every second. At 0, set to nil and start real scroll.
- **About window credit:** override `CommandGroup(replacing: .appInfo)` in the app scene. Use `NSAttributedString` with `.link: URL(string: "https://santiagoalonso.com")!`.

## On Stuck

If truly stuck (same error after two different approaches):
1. Check `~/.claude/skills/macos-app-scaffold/SKILL.md` for the macOS-specific pattern
2. Check `~/.claude/skills/swiftui-expert-skill/references/` for the relevant API
3. Check `~/.claude/references/macos-niche-rules.md`
4. Use the Task tool to spawn a `fullstack-developer` subagent with the specific error
5. If still stuck, mark the feature in `deferred_to_v1`, commit what works, move on

## Reporting

After Phase 6, write `BUILD_REPORT.md` at `/Users/san/Projects/moody-clone/BUILD_REPORT.md` using the template at `~/.claude/skills/v0-mac/references/report-template.md`.

Once the report is written and committed, emit the completion promise on its own line:

```
V0_MAC_COMPLETE
```

---

Begin with Phase 1. Work through the phases in order. Do not ask the user anything — the plan and run contract are your sole inputs.
