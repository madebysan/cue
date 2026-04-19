import SwiftUI

struct ContentView: View {
    @AppStorage("defaultSpeed") private var speed: Double = 80
    @AppStorage("defaultTextSize") private var textSize: Double = 24
    @AppStorage("defaultVoiceMode") private var voiceMode: Bool = false
    @AppStorage("voiceSensitivity") private var sensitivity: Double = 0.08

    @State private var script: String = """
    Paste your script here.

    Press the spacebar to start scrolling. Press it again — or Escape — to pause.

    Turn on the microphone to auto-scroll while you speak.
    """

    @StateObject private var scroll = ScrollController()
    @StateObject private var mic = MicLevelMonitor()

    @State private var countdown: Int? = nil
    @State private var voiceRunActive: Bool = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            if voiceMode {
                VStack(spacing: 4) {
                    VolumeMeterView(
                        level: mic.level,
                        threshold: Float(sensitivity),
                        active: voiceRunActive || scroll.isScrolling
                    )
                    HStack {
                        Text(String(format: "level %.2f", mic.level))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(String(format: "threshold %.2f", sensitivity))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            scriptArea
        }
        .frame(minWidth: 420, minHeight: 240)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { scroll.speed = speed }
        .onChange(of: speed) { _, new in scroll.speed = new }
        .onChange(of: voiceMode) { _, on in
            if on {
                Task { await mic.start() }
            } else {
                mic.stop()
                voiceRunActive = false
            }
        }
        .onChange(of: mic.level) { _, level in
            handleVoiceLevel(level)
        }
        .onKeyPress(.space) {
            guard !editorFocused else { return .ignored }
            toggleScroll()
            return .handled
        }
        .onKeyPress(.escape) {
            if scroll.isScrolling || countdown != nil || voiceRunActive {
                pauseEverything()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button(action: toggleScroll) {
                Image(systemName: playButtonSymbol)
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .help(playButtonHelp)

            Button(action: { scroll.reset() }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset to top")
            .disabled(scroll.offset == 0 && !scroll.isScrolling)

            Divider().frame(height: 16)

            HStack(spacing: 6) {
                Image(systemName: "hare.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Slider(value: $speed, in: 20...200)
                    .frame(width: 120)
            }
            .help("Scroll speed")

            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Slider(value: $textSize, in: 14...48)
                    .frame(width: 80)
            }
            .help("Text size")

            Divider().frame(height: 16)

            Toggle(isOn: $voiceMode) {
                Image(systemName: voiceMode ? "mic.fill" : "mic.slash.fill")
            }
            .toggleStyle(.button)
            .help("Voice-activated scrolling")

            if voiceMode {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Slider(value: $sensitivity, in: 0.05...0.5)
                        .frame(width: 80)
                }
                .help("Voice sensitivity threshold")
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var playButtonSymbol: String {
        if countdown != nil { return "stop.fill" }
        return scroll.isScrolling || voiceRunActive ? "pause.fill" : "play.fill"
    }

    private var playButtonHelp: String {
        if scroll.isScrolling || voiceRunActive || countdown != nil {
            return "Pause (Space)"
        }
        return "Start scrolling (Space)"
    }

    // MARK: - Script area

    private var scriptArea: some View {
        ZStack {
            ScrollView {
                TextEditor(text: $script)
                    .font(.system(size: textSize))
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(minHeight: 600, alignment: .top)
                    .offset(y: -scroll.offset)
            }
            .background(Color(nsColor: .textBackgroundColor))

            if let count = countdown, count > 0 {
                CountdownView(value: count)
            }
        }
    }

    // MARK: - Actions

    private func toggleScroll() {
        if countdown != nil {
            withAnimation(.easeInOut(duration: 0.25)) { countdown = nil }
            return
        }
        if scroll.isScrolling || voiceRunActive {
            scroll.stop()
            voiceRunActive = false
            return
        }
        startWithCountdown()
    }

    private func pauseEverything() {
        scroll.stop()
        voiceRunActive = false
        withAnimation(.easeInOut(duration: 0.25)) { countdown = nil }
    }

    private func startWithCountdown() {
        countdown = 3
        tickCountdown()
    }

    private func tickCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let c = countdown else { return }
            if c > 1 {
                withAnimation(.easeInOut(duration: 0.25)) { countdown = c - 1 }
                tickCountdown()
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { countdown = nil }
                if voiceMode {
                    // Voice-gated: scroll only advances when mic level > threshold.
                    // handleVoiceLevel starts/stops scroll based on mic input.
                    voiceRunActive = true
                } else {
                    scroll.start()
                }
            }
        }
    }

    private func handleVoiceLevel(_ level: Float) {
        // Voice-gated modulation: while voiceRunActive, pause when silent, resume when loud.
        // Play is what starts the scroll; voice just gates whether the timer ticks advance.
        guard voiceMode, voiceRunActive else { return }
        let above = level > Float(sensitivity)
        if above && !scroll.isScrolling {
            scroll.start()
        } else if !above && scroll.isScrolling {
            scroll.stop()
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 520, height: 340)
}
