import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    var keyMonitor: Any?

    // Global key handlers for the window — NSPanel doesn't reliably deliver
    // key events to SwiftUI's .onKeyPress, so we use a local NSEvent monitor.
    static var onSpacePressed: () -> Void = {}
    static var onEscapePressed: () -> Void = {}
    static var isEditorFocused: () -> Bool = { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("applicationDidFinishLaunching")
        Logger.shared.log("bundle: \(Bundle.main.bundleIdentifier ?? "?"), executable: \(Bundle.main.executablePath ?? "?")")
        Logger.shared.log("home: \(FileManager.default.homeDirectoryForCurrentUser.path)")

        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 520, height: 320),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
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
            // 49 = space, 53 = escape
            if event.keyCode == 49 {
                if AppDelegate.isEditorFocused() {
                    return event  // let the text editor receive spaces
                }
                Logger.shared.log("space key captured by monitor")
                AppDelegate.onSpacePressed()
                return nil
            }
            if event.keyCode == 53 {
                Logger.shared.log("escape key captured by monitor")
                AppDelegate.onEscapePressed()
                return nil
            }
            return event
        }
        Logger.shared.log("key monitor installed")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
