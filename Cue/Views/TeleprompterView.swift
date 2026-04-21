import AppKit
import SwiftUI

/// NSTextView-backed teleprompter surface. Supports editing, programmatic
/// scrolling to an exact character offset (for transcription-driven sync),
/// and arrow-key manual scroll.
struct TeleprompterView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    /// Character offset to keep visible (e.g. where the user currently is in the script).
    /// When nil, no programmatic scroll happens.
    var focusCharOffset: Int?
    /// Whether the editor is currently focused (for disabling spacebar-as-play).
    var onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 24, height: 16)
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = NSColor.labelColor
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= text.count {
                textView.setSelectedRange(selectedRange)
            }
            context.coordinator.lastScrolledOffset = -1  // text changed, re-scroll next time
        }
        if textView.font?.pointSize != fontSize {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }

        // Only scroll when the offset actually changes — prevents layout loops from
        // rapid-fire SwiftUI re-renders during speech recognition.
        guard let offset = focusCharOffset,
              !context.coordinator.isFocused,
              !textView.string.isEmpty,
              offset >= 0,
              offset <= textView.string.count,
              offset != context.coordinator.lastScrolledOffset,
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
        guard visibleHeight > 0 else { return }
        let targetTop = max(0, rect.origin.y - visibleHeight * 0.35)
        let maxY = max(0, textView.bounds.height - visibleHeight)
        let clamped = min(targetTop, maxY)
        // Direct setBoundsOrigin (no animator) — avoids in-flight animation
        // interfering with the next partial-result update.
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clamped))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textBinding: Binding<String>
        var onFocusChange: (Bool) -> Void
        weak var textView: NSTextView?
        var isFocused: Bool = false
        var lastScrolledOffset: Int = -1

        init(text: Binding<String>, onFocusChange: @escaping (Bool) -> Void) {
            self.textBinding = text
            self.onFocusChange = onFocusChange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            textBinding.wrappedValue = tv.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
            onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused = false
            onFocusChange(false)
        }
    }
}

/// Small helper to scroll the teleprompter manually (e.g. arrow keys).
enum TeleprompterScrollDirection {
    case up, down
}
