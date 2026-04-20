# Cue — /dumb Plan (historical)

## What it actually is
A floating window with scrolling text. Press spacebar to start, press spacebar to pause. That's the product.

## The question /dumb asks
> "What's the dumbest version that still works?"

**Answer:** strip every "smart" feature. Voice activation is the hardest, most fragile, most novel feature in Moody. It's also the one you've never built before. So in the dumb version, it's **not in v1**. Spacebar is fine. Teleprompter apps existed before voice detection existed.

## Features — six, total
1. A `TextEditor`. You paste text into it.
2. A speed slider (pixels per second).
3. **Spacebar** toggles auto-scroll.
4. Window floats above all apps, across all Spaces, over full-screen apps.
5. Window is invisible to screen share.
6. **Cmd+drag** moves the window.

## What's cut from the v0-mac plan — and why
| Feature in v0-mac | Cut? | Reason |
|-------------------|------|--------|
| Voice-activated scroll (AVAudioEngine) | **Cut** | Hardest + most fragile feature. V2. |
| Volume meter bar | **Cut** | No mic in v1, so no meter |
| Mic toggle, sensitivity slider | **Cut** | No mic |
| 3-2-1 countdown | **Cut** | Just press spacebar. It starts. |
| Esc to pause | **Cut** | Spacebar is a toggle — one key, one job |
| Text size slider | **Cut** | Hardcode 24pt. Works for 99% of scripts. |
| Settings window | **Cut** | The speed slider in the main window IS the settings |
| UserDefaults persistence | **Cut** | v1 doesn't remember state between launches. Who cares. |
| `ScrollState` enum, `MicLevelMonitor` service, `ScrollController` service | **Cut** | No services, no controllers. One `@State` bool = isScrolling. |
| About window | **Kept (minimal)** | Required by CLAUDE.md. Standard NSAboutPanel with one clickable credit line. 8 lines of code. |

## What's kept
- NSPanel with floating level, canJoinAllSpaces, fullScreenAuxiliary, sharingType = .none, isMovableByWindowBackground = true
- TextEditor, slider, spacebar handler

**Every one of those items is one line of code.** They're kept because the marginal cost is zero and they're the actual value prop (the thing that makes it useful vs. a regular text editor).

## Tech
- One SwiftUI `ContentView`
- One `AppDelegate` that configures the NSPanel
- No models, no services, no view subfolders
- No AVAudioEngine at all
- No UserDefaults
- macOS 14.0+

## Entitlements
```xml
com.apple.security.app-sandbox
```
That's it. **No microphone entitlement.** No privacy string. No permission prompt on first launch.

## Files
```
cue/
├── project.yml
├── Cue/
│   ├── CueApp.swift      # @main + AppDelegate
│   └── ContentView.swift         # everything else
├── Cue/Info.plist
└── Cue/Cue.entitlements
```
**Three Swift files, including the @main.** That's the whole app.

## Line count estimate
~120-150 lines of Swift, total.

## run_contract
```yaml
run_contract:
  max_iterations: 15
  completion_promise: "V0_MAC_COMPLETE"
  on_stuck: defer_and_continue
  on_ambiguity: choose_simpler_option
  on_regression: revert_to_last_clean_commit
  human_intervention: never
  macos_target: "14.0"
  app_shape: floating_utility
  sandbox: true
  signing: skip
  visual_qa_max_passes: 1
  phase_skip:
    visual_qa: false
    polish: true        # skip polish — it's a text window, nothing to polish
    dmg: true
  entitlements: []
  complexity_overrides:
    scroll: "single @State bool + Timer.publish, no controller"
    drag: "isMovableByWindowBackground"
```

## Estimated scope
- 3 Swift files, ~120 lines total
- 8-12 ralph-loop iterations (~15-20 minutes)

## The honest trade-off
**This is not Moody.** It's a scrolling-text window. If the voice-activated scrolling is the reason you're cloning Moody, this plan is wrong for you — pick the v0-mac plan.

If the reason is "I want a floating teleprompter I can paste text into and scroll with a keyboard shortcut, and Moody is charging $29 for that," this plan is exactly right. It builds the useful 80% in 15 minutes instead of 45, and you can add voice as a v2 feature once you've used the thing for a week and know what you actually want.

## v2 path, if this works
1. Add mic entitlement + AVAudioEngine level detection → volume meter
2. Add threshold-based voice scroll (one more @State, one comparison)
3. Add text size slider if 24pt isn't right
4. Add settings window only if multiple settings accumulate
