import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    var keyMonitor: Any?

    // Global key handlers for the window — NSPanel doesn't reliably deliver
    // key events to SwiftUI's .onKeyPress, so we use a local NSEvent monitor.
    static var onSpacePressed: () -> Void = {}
    static var onEscapePressed: () -> Void = {}
    static var onArrowUp: () -> Void = {}
    static var onArrowDown: () -> Void = {}
    static var isEditorFocused: () -> Bool = { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("applicationDidFinishLaunching")
        Logger.shared.log("bundle: \(Bundle.main.bundleIdentifier ?? "?"), executable: \(Bundle.main.executablePath ?? "?")")
        Logger.shared.log("home: \(FileManager.default.homeDirectoryForCurrentUser.path)")

        // Activate the app so CoreAudio/TCC routes mic input to us.
        // macOS 26 doesn't reliably hand mic audio to non-activating panels.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 520, height: 320),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "MoodyClone"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        let qaVisible = CommandLine.arguments.contains("--qa-visible")
        panel.sharingType = qaVisible ? .readOnly : .none
        panel.hidesOnDeactivate = false

        panel.contentView = NSHostingView(rootView: ContentView())
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // Install a local key monitor so spacebar / escape work even when
        // the NSPanel doesn't activate the app.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Key codes: 49=space, 53=escape, 125=down arrow, 126=up arrow
            let editorFocused = AppDelegate.isEditorFocused()

            switch event.keyCode {
            case 49:
                if editorFocused { return event }
                AppDelegate.onSpacePressed()
                return nil
            case 53:
                AppDelegate.onEscapePressed()
                return nil
            case 126: // up arrow
                if editorFocused { return event }
                AppDelegate.onArrowUp()
                return nil
            case 125: // down arrow
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
}
