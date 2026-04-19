import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultSpeed") private var defaultSpeed: Double = 80
    @AppStorage("defaultTextSize") private var defaultTextSize: Double = 24
    @AppStorage("defaultVoiceMode") private var defaultVoiceMode: Bool = false
    @AppStorage("voiceSensitivity") private var voiceSensitivity: Double = 0.15

    var body: some View {
        Form {
            Section("Defaults") {
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $defaultSpeed, in: 20...200)
                            .frame(width: 180)
                        Text("\(Int(defaultSpeed)) px/s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }

                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $defaultTextSize, in: 14...48)
                            .frame(width: 180)
                        Text("\(Int(defaultTextSize)) pt")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }

                Toggle("Enable voice-activated scrolling by default", isOn: $defaultVoiceMode)
            }

            Section("Voice sensitivity") {
                LabeledContent("Threshold") {
                    HStack {
                        Slider(value: $voiceSensitivity, in: 0.05...0.5)
                            .frame(width: 180)
                        Text(String(format: "%.2f", voiceSensitivity))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                Text("Higher = less sensitive (harder to trigger scroll in noisy rooms).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 340)
    }
}

#Preview {
    SettingsView()
}
