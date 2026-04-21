# TeleprompterView

## Purpose

The scrolling text surface of the app. Bridges SwiftUI to AppKit's `NSTextView` so we can query glyph positions and scroll to an exact character offset — something SwiftUI's `TextEditor` cannot do directly.

## Location

`Cue/Views/TeleprompterView.swift` (126 lines)

## Interface

```swift
struct TeleprompterView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var focusCharOffset: Int?
    var onFocusChange: (Bool) -> Void
}
```

- `text` — two-way binding to `ContentView.script`. User edits flow back through the `Coordinator`.
- `fontSize` — live-updatable from the Settings slider.
- `focusCharOffset` — the character position to keep visible. `nil` means "don't scroll programmatically — user is editing or app is paused".
- `onFocusChange` — called when the text view becomes/loses first responder. Used to disable spacebar-as-play while typing.

## Internal Design

### Why NSTextView, not SwiftUI TextEditor

SwiftUI's `TextEditor` does not expose its underlying layout manager. You can't ask it "what's the pixel position of character N?" — which is exactly what we need to scroll to an exact word in the script.

`NSTextView` has `layoutManager.boundingRect(forGlyphRange:in:)`, which takes an `NSRange` and returns a `CGRect`. Wrap it in an `NSScrollView`, wrap that in `NSViewRepresentable`, and SwiftUI can use it with two-way text binding.

### The scroll-to-offset logic

`updateNSView(_:context:)` runs whenever any observed SwiftUI state changes. The scroll path is:

```swift
guard let offset = focusCharOffset,
      !context.coordinator.isFocused,        // don't fight the user
      !textView.string.isEmpty,
      offset >= 0,
      offset <= textView.string.count,
      offset != context.coordinator.lastScrolledOffset,  // <-- key optimization
      let lm = textView.layoutManager,
      let tc = textView.textContainer
else { return }

context.coordinator.lastScrolledOffset = offset

lm.ensureLayout(for: tc)
let nsRange = NSRange(location: offset, length: 0)
let glyphRange = lm.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)
guard glyphRange.location != NSNotFound else { return }

var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
rect.origin.y += textView.textContainerInset.height

let visibleHeight = scrollView.contentView.bounds.height
let targetTop = max(0, rect.origin.y - visibleHeight * 0.35)
let maxY = max(0, textView.bounds.height - visibleHeight)
let clamped = min(targetTop, maxY)

scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clamped))
scrollView.reflectScrolledClipView(scrollView.contentView)
```

**Critical details:**

- **`offset != lastScrolledOffset` guard.** SwiftUI re-renders the parent view on every `matcher.currentWordIndex` change (many times per second during speech). Without this guard, we'd issue a scroll command on every render, even when the offset hadn't actually moved — a known layout-loop trigger.
- **`setBoundsOrigin` directly, not `animator().setBoundsOrigin`.** Animated scroll plus rapid-fire offset updates from partial speech results creates in-flight animation conflicts. Direct set means no interpolation, which looks slightly less smooth but eliminates the crash surface.
- **Aim for the matched word ~35% down from the top of the visible area** (`- visibleHeight * 0.35`). Keeps a bit of context visible above the current position so the user can see where they just were.
- **`lm.ensureLayout(for: tc)` before querying.** The layout manager sometimes hasn't caught up when the text changes. Forcing layout guarantees `boundingRect` returns a valid rect.
- **Guard against `glyphRange.location == NSNotFound`.** Happens rarely during the split-second between text assignment and layout. Early return prevents a crash here.

### The Coordinator

Classic `NSViewRepresentable` pattern:

```swift
final class Coordinator: NSObject, NSTextViewDelegate {
    var textBinding: Binding<String>
    var onFocusChange: (Bool) -> Void
    weak var textView: NSTextView?
    var isFocused: Bool = false
    var lastScrolledOffset: Int = -1
}
```

The Coordinator holds:

- **The text binding** — `textDidChange(_:)` pushes edits back to SwiftUI
- **The focus state** — `textDidBeginEditing` / `textDidEndEditing` surface to `ContentView` via `onFocusChange`
- **`lastScrolledOffset`** — stored here instead of on the struct because SwiftUI re-creates the struct on every re-render, but the Coordinator persists for the lifetime of the view

### Text + font updates

`updateNSView` also reconciles `text` (update only if changed, preserve cursor position) and `fontSize` (update only if changed). Changing text resets `lastScrolledOffset` to `-1` so the next scroll triggers fresh.

## Constraints

- **Programmatic scroll is disabled while the user is editing.** `context.coordinator.isFocused` guard. This means if the user clicks inside to fix a typo while speaking, the scroll freezes until they click out. Intentional.
- **Arrow-key manual scroll doesn't route through this view.** `ContentView.manualScroll(by:)` nudges the matcher's `currentWordIndex` by ±5 tokens, which triggers a new offset, which triggers this view to scroll. Less direct than native arrow-key scrolling but keeps the matcher's position in sync.
- **Very large scripts may stutter.** Every offset change forces `ensureLayout` on the visible region, which for a 10,000-word script could hitch. No paginated layout in v0.
- **`NSScrollView` vs `SwiftUI ScrollView`** — this is a pure AppKit scroll view. `SwiftUI ScrollViewReader` has no visibility into it.

## Dependencies

- `AppKit` for `NSTextView`, `NSScrollView`, `NSLayoutManager`
- `SwiftUI` for `NSViewRepresentable`, `Binding`

## Related

- [TranscriptionMatcher](TranscriptionMatcher.md) — source of `focusCharOffset`
- [Design-Decisions](../Design-Decisions.md) — DD-004 (NSTextView over TextEditor)
- [Constraints and Tradeoffs](../Constraints-and-Tradeoffs.md) — the scroll layout-loop history
