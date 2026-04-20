import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    var keyMonitor: Any?

    static var onSpacePressed: () -> Void = {}
    static var onEscapePressed: () -> Void = {}
    static var onArrowUp: () -> Void = {}
    static var onArrowDown: () -> Void = {}
    static var isEditorFocused: () -> Bool = { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("applicationDidFinishLaunching")
        Logger.shared.log("bundle: \(Bundle.main.bundleIdentifier ?? "?"), executable: \(Bundle.main.executablePath ?? "?")")
        Logger.shared.log("home: \(FileManager.default.homeDirectoryForCurrentUser.path)")

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let windowSize = NSSize(width: 640, height: 140)
        let initialOrigin = Self.topCenterOrigin(for: windowSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: initialOrigin, size: windowSize),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        let qaVisible = CommandLine.arguments.contains("--qa-visible")
        panel.sharingType = qaVisible ? .readOnly : .none
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 420, height: 110)

        panel.contentView = NSHostingView(rootView: ContentView())
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let editorFocused = AppDelegate.isEditorFocused()
            switch event.keyCode {
            case 49:
                if editorFocused { return event }
                AppDelegate.onSpacePressed()
                return nil
            case 53:
                AppDelegate.onEscapePressed()
                return nil
            case 126:
                if editorFocused { return event }
                AppDelegate.onArrowUp()
                return nil
            case 125:
                if editorFocused { return event }
                AppDelegate.onArrowDown()
                return nil
            default:
                return event
            }
        }
        Logger.shared.log("key monitor installed")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Centers a window horizontally on the main screen with its top edge
    /// pinned at the very top (so it appears to extend out of the notch area).
    private static func topCenterOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 200, y: 600)
        }
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        // In AppKit, origin is bottom-left. Put the window's TOP at the screen's top.
        let y = frame.maxY - size.height
        return NSPoint(x: x, y: y)
    }
}
