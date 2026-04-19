import AppKit
import SwiftUI

@main
struct MoodyCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MoodyClone") {
                    Self.showAboutPanel()
                }
            }
        }
    }

    private static func showAboutPanel() {
        let url = URL(string: "https://santiagoalonso.com")!
        let credits = NSMutableAttributedString(
            string: "Made by santiagoalonso.com",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
                .link: url,
                .cursor: NSCursor.pointingHand
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "MoodyClone",
            .applicationVersion: "0.1.0"
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
