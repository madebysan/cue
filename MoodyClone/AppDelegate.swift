import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?

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
        // Invisible to screen share / screenshots — Moody's signature privacy feature.
        // `--qa-visible` launch arg disables this for visual QA builds only.
        let qaVisible = CommandLine.arguments.contains("--qa-visible")
        panel.sharingType = qaVisible ? .readOnly : .none
        panel.hidesOnDeactivate = false

        panel.contentView = NSHostingView(rootView: ContentView())
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
