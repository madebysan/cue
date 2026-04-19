import AppKit
import SwiftUI

struct ContentView: View {
    @AppStorage("defaultTextSize") private var textSize: Double = 24
    @AppStorage("defaultVoiceMode") private var voiceMode: Bool = false
    @AppStorage("fallbackSpeed") private var fallbackSpeed: Double = 60  // used when voice mode is off

    @State private var script: String = """
    Paste your script here.

    Press the spacebar to start — the app will listen to you read and scroll the text to match your pace. Go off-script, pause, or improvise freely; it'll catch up when you return to the script.

    Press space or escape to pause. Arrow keys scroll manually if you need to override.
    """

    @StateObject private var mic = MicLevelMonitor()
    @StateObject private var speech = SpeechTranscriber()
    @StateObject private var matcher = TranscriptionMatcher()

    @State private var countdown: Int? = nil
    @State private var isRunning: Bool = false
    @State private var editorFocused: Bool = false
    @State private var manualScrollOffset: CGFloat? = nil
    @State private var manualTick: Int = 0  // bump to force TeleprompterView to scroll manually

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            if voiceMode {
                progressBar
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }

            ZStack {
                TeleprompterView(
                    text: $script,
                    fontSize: textSize,
                    focusCharOffset: focusOffset,
                    onFocusChange: { editorFocused = $0 }
                )
                .onChange(of: script) { _, newText in
                    matcher.setScript(newText)
                }

                if let count = countdown, count > 0 {
                    CountdownView(value: count)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            matcher.setScript(script)
            hookUpMicToSpeech()
            AppDelegate.onSpacePressed = { togglePlay() }
            AppDelegate.onEscapePressed = { pauseEverything() }
            AppDelegate.onArrowUp = { manualScroll(by: -80) }
            AppDelegate.onArrowDown = { manualScroll(by: 80) }
            AppDelegate.isEditorFocused = { editorFocused }
        }
        .onChange(of: editorFocused) { _, f in
            AppDelegate.isEditorFocused = { f }
        }
        .onChange(of: voiceMode) { _, on in
            Logger.shared.log("voiceMode changed to \(on)")
            if on {
                // Request speech permission + start mic.
                speech.requestAuthorization { granted in
                    if granted {
                        mic.start()
                    } else {
                        Logger.shared.log("speech auth NOT granted — staying in mic-only mode")
                        mic.start()  // at least get the volume meter
                    }
                }
            } else {
                speech.stop()
                mic.stop()
                stopRunning()
            }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button(action: togglePlay) {
                Image(systemName: playSymbol).frame(width: 20)
            }
            .buttonStyle(.borderless)
            .help(playHelp)

            Button(action: resetProgress) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset to start")

            Divider().frame(height: 16)

            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Slider(value: $textSize, in: 14...48).frame(width: 100)
            }
            .help("Text size")

            if !voiceMode {
                HStack(spacing: 6) {
                    Image(systemName: "hare.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Slider(value: $fallbackSpeed, in: 20...200).frame(width: 100)
                }
                .help("Fallback scroll speed (voice mode off)")
            }

            Divider().frame(height: 16)

            Toggle(isOn: $voiceMode) {
                Image(systemName: voiceMode ? "mic.fill" : "mic.slash.fill")
            }
            .toggleStyle(.button)
            .help(voiceMode ? "Voice-following on — app listens and scrolls to your position" : "Voice-following off — manual scrolling only")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            VolumeMeterView(level: mic.level, threshold: 0.05, active: isRunning)
            HStack {
                Text("\(matcher.currentWordIndex) / \(matcher.totalTokens) words")
                Spacer()
                Text(speechStatus)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            if let err = speech.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var speechStatus: String {
        switch speech.authStatus {
        case .authorized: return speech.isRunning ? "listening" : "speech idle"
        case .denied: return "speech denied"
        case .restricted: return "speech restricted"
        case .notDetermined: return "speech —"
        @unknown default: return "speech ?"
        }
    }

    private var playSymbol: String {
        if countdown != nil { return "stop.fill" }
        return isRunning ? "pause.fill" : "play.fill"
    }

    private var playHelp: String {
        if isRunning || countdown != nil { return "Pause (Space)" }
        return "Start (Space)"
    }

    private var focusOffset: Int? {
        // Scroll to the current matched position in voice mode; otherwise let the user control.
        guard voiceMode, isRunning, !editorFocused else { return nil }
        return matcher.currentCharOffset
    }

    // MARK: - Actions

    private func togglePlay() {
        Logger.shared.log("togglePlay — voiceMode=\(voiceMode) isRunning=\(isRunning) countdown=\(countdown.map(String.init) ?? "nil") editorFocused=\(editorFocused)")
        if countdown != nil {
            withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
            return
        }
        if isRunning {
            stopRunning()
            return
        }
        startWithCountdown()
    }

    private func pauseEverything() {
        stopRunning()
        withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
    }

    private func resetProgress() {
        matcher.reset()
    }

    private func startWithCountdown() {
        countdown = 3
        tickCountdown()
    }

    private func tickCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let c = countdown else { return }
            if c > 1 {
                withAnimation(.easeInOut(duration: 0.2)) { countdown = c - 1 }
                tickCountdown()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
                beginRunning()
            }
        }
    }

    private func beginRunning() {
        isRunning = true
        if voiceMode {
            speech.start()
        }
        Logger.shared.log("beginRunning — voiceMode=\(voiceMode)")
    }

    private func stopRunning() {
        if isRunning {
            Logger.shared.log("stopRunning")
        }
        isRunning = false
        speech.stop()
    }

    private func hookUpMicToSpeech() {
        // Route mic audio into speech recognizer.
        mic.onAudioBuffer = { [weak speech] buffer, _ in
            speech?.append(buffer: buffer)
        }
        // Route recognized text to the matcher.
        speech.onRecognized = { [weak matcher] text in
            matcher?.ingest(text)
        }
    }

    private func manualScroll(by delta: CGFloat) {
        // When user hits arrows, we nudge the matcher's position by N tokens
        // so the auto-follow doesn't immediately yank it back.
        let tokensPerStep = delta > 0 ? 5 : -5
        let newIndex = max(0, min(matcher.totalTokens, matcher.currentWordIndex + tokensPerStep))
        Logger.shared.log("manualScroll delta=\(delta) → word \(newIndex)")
        matcher.setCurrentIndex(newIndex)
    }
}

#Preview {
    ContentView()
        .frame(width: 520, height: 340)
}
