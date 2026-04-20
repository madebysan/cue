import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    var keyMonitor: Any?
    var statusItem: NSStatusItem?

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

        let defaultSize = NSSize(width: 380, height: 100)
        let initialOrigin = Self.topCenterOrigin(for: defaultSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: initialOrigin, size: defaultSize),
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
        #if DEBUG
        let qaVisible = CommandLine.arguments.contains("--qa-visible")
        panel.sharingType = qaVisible ? .readOnly : .none
        #else
        panel.sharingType = .none
        #endif
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 360, height: 90)
        // Persist size + position between launches.
        panel.setFrameAutosaveName("MoodyClonePanel")

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

        // Discreet menu bar icon so the user can confirm the app is running
        // and toggle window visibility. Intentionally not a microphone or quote icon.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "MoodyClone")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show/Hide Window", action: #selector(toggleWindow), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleWindow() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openSettings() {
        // Triggers SwiftUI's Settings scene via the standard app menu item.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
