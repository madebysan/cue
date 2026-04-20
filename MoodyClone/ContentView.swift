import AppKit
import SwiftUI

struct ContentView: View {
    @AppStorage("defaultTextSize") private var textSize: Double = 18
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.92

    @State private var script: String = """
    Welcome to MoodyClone, a teleprompter that listens to you instead of running on a timer. Start by pressing the spacebar or clicking the play button. A three-two-one countdown will appear, and then the app will begin listening. As you speak, the text will scroll to keep your current position visible. You do not need to match the speed to your reading pace. Just talk normally. The app will follow.

    You can test how well the matching works by changing your cadence. Try speaking quickly, then slowly. Try pausing for a full second between sentences. Try emphasizing certain words, then mumbling through others. The scroll should track you through all of these variations without getting confused. If the recognizer mishears a word, the fuzzy matching should still advance the position. If you stumble or backtrack, the scroll should hold steady rather than jump around.

    Now, try going off script. Stop reading these sentences and start talking about something completely different. Describe your day, or explain what you had for breakfast, or simply count to ten. The scroll will freeze in place because the words you are saying do not match anywhere in the script. When you return to reading the script, the position should resume exactly where you left off. This behavior is intentional. The app should never guess wildly when it does not know where you are.

    Next, try skipping ahead. Jump down two paragraphs and start reading from a different point. The app should notice that your spoken words match a location further down in the script, and the scroll should jump forward to catch up with you. This is the behavior you want when you deliver a talk from memory and only glance at the teleprompter occasionally. You set the pace. The app adapts.

    Let us talk about why this exists. Traditional teleprompters scroll at a fixed speed, measured in pixels per second or words per minute. The operator has to calibrate the speed for each speaker, and the speaker has to match the machine. If the operator sets the pace too fast, the speaker falls behind and looks frantic. If the operator sets it too slow, the speaker rushes ahead and waits awkwardly for the next line. Good teleprompter operators are rare and expensive because this calibration is a real craft.

    Speech recognition removes the operator from the loop. The app listens to what you are actually saying and moves the text to match. It works at any pace, adjusts to emphasis and pauses automatically, and never drifts out of sync over a long reading. The cost is that it requires a good microphone, a quiet room, and a language model that knows your accent. Apple's on-device speech recognition handles English, Spanish, French, German, Mandarin, Japanese, and a dozen other languages, all without sending your voice to a server.

    If you need to override the automatic tracking, you have several options. The up and down arrow keys will nudge the current position backward or forward by a few words. The escape key pauses everything immediately. Clicking inside this text area and using a trackpad or mouse wheel will scroll manually, though the app will try to re-center you the moment you start speaking again. If you want to edit the script while running, pause first, then click in and make your changes, then resume.

    Finally, a note on privacy. MoodyClone uses your microphone and Apple's speech recognition. Audio is processed locally when on-device recognition is available, and never stored. Your scripts stay on your machine. The window itself can be made invisible to screen recording and screen sharing, so you can rehearse during a video call without your audience seeing the prompter. That is what made Moody interesting in the first place, and this clone keeps that feature front and center.

    You have reached the end of the test script. Congratulations. If the scroll tracked you all the way here without getting stuck, the app is working correctly. If it stuck partway, note where and let the developer know. Now go practice your actual script.
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
            ZStack(alignment: .top) {
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
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0)
            )
            .fill(.black.opacity(backgroundOpacity))
        )
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: 18, bottomTrailing: 18, topTrailing: 0)
            )
        )
        .preferredColorScheme(.dark)
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
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button(action: togglePlay) {
                Image(systemName: playSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(playHelp)

            Button(action: resetProgress) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Reset to start")

            if isRunning {
                Text("\(matcher.currentWordIndex)/\(matcher.totalTokens)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 12)

            HStack(spacing: 4) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Slider(value: $textSize, in: 14...48).frame(width: 120)
            }
            .help("Text size")

            Spacer()

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close (⌘Q)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
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
        // Scroll to the current matched position while running; otherwise let the user control.
        guard isRunning, !editorFocused else { return nil }
        return matcher.currentCharOffset
    }

    // MARK: - Actions

    private func togglePlay() {
        Logger.shared.log("togglePlay — isRunning=\(isRunning) micRunning=\(mic.isRunning) countdown=\(countdown.map(String.init) ?? "nil") editorFocused=\(editorFocused)")
        if countdown != nil {
            withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
            return
        }
        if isRunning {
            stopRunning()
            return
        }
        // Make sure the mic is ready before the countdown ends.
        if !mic.isRunning {
            speech.requestAuthorization { _ in mic.start() }
        }
        startWithCountdown()
    }

    private func pauseEverything() {
        stopRunning()
        withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
    }

    private func resetProgress() {
        // Defensive: stop any in-flight speech/scroll first so we don't reset
        // position while an update is mid-flight (can confuse SwiftUI layout).
        Logger.shared.log("resetProgress")
        stopRunning()
        withAnimation(.easeInOut(duration: 0.2)) { countdown = nil }
        matcher.reset()
    }

    private func startWithCountdown() {
        Logger.shared.log("startWithCountdown — setting countdown=3")
        countdown = 3
        Logger.shared.log("countdown set, scheduling tick")
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
        speech.start()
        Logger.shared.log("beginRunning")
    }

    private func stopRunning() {
        if isRunning {
            Logger.shared.log("stopRunning")
        }
        isRunning = false
        speech.stop()
        // Keep mic running between sessions so the orange dot stays consistent
        // and play→speech starts instantly. User quitting the app stops it.
    }

    private func hookUpMicToSpeech() {
        let speechRef = speech
        let matcherRef = matcher
        mic.onSampleBuffer = { sb in
            speechRef.append(sampleBuffer: sb)
        }
        speech.onRecognized = { text in
            matcherRef.ingest(text)
        }
        Logger.shared.log("hookUpMicToSpeech — mic.onSampleBuffer set=\(mic.onSampleBuffer != nil), speech.onRecognized set=\(speech.onRecognized != nil)")
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
