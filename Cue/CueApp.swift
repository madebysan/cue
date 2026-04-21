import AppKit
import AVFoundation
import Speech
import SwiftUI

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "sparkle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Cue") {
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
            .applicationName: "Cue",
            .applicationVersion: "0.1.0"
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuBarContent: View {
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()

    var body: some View {
        Button("Show/Hide Window") {
            Logger.shared.log("CUE-DBG: MenuBar → Show/Hide Window tapped")
            AppDelegate.shared?.toggleWindow()
        }
        .keyboardShortcut("h")

        Divider()

        Button("Microphone: \(label(for: micStatus))") {
            Logger.shared.log("CUE-DBG: MenuBar → Mic tapped; status=\(micStatus.rawValue)")
            handleMicTap()
        }

        Button("Speech Recognition: \(label(for: speechStatus))") {
            Logger.shared.log("CUE-DBG: MenuBar → Speech tapped; status=\(speechStatus.rawValue)")
            handleSpeechTap()
        }

        if micStatus == .notDetermined || speechStatus == .notDetermined {
            Button("Request Permissions…") {
                Logger.shared.log("CUE-DBG: MenuBar → Request Permissions tapped")
                handleMicTap()
                handleSpeechTap()
            }
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Cue") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func handleMicTap() {
        if micStatus == .notDetermined {
            NSApp.activate(ignoringOtherApps: true)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Logger.shared.log("CUE-DBG: mic requestAccess returned granted=\(granted)")
                DispatchQueue.main.async {
                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func handleSpeechTap() {
        if speechStatus == .notDetermined {
            NSApp.activate(ignoringOtherApps: true)
            SFSpeechRecognizer.requestAuthorization { status in
                Logger.shared.log("CUE-DBG: speech requestAuthorization returned status=\(status.rawValue)")
                DispatchQueue.main.async {
                    speechStatus = status
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        }
    }

    private func label(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "✓ Granted"
        case .denied: return "✗ Denied"
        case .restricted: return "⛔ Restricted"
        case .notDetermined: return "— Not requested yet"
        @unknown default: return "?"
        }
    }

    private func label(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "✓ Granted"
        case .denied: return "✗ Denied"
        case .restricted: return "⛔ Restricted"
        case .notDetermined: return "— Not requested yet"
        @unknown default: return "?"
        }
    }
}
