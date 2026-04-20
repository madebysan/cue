import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTextSize") private var textSize: Double = 18
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.92

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Background opacity") {
                    HStack {
                        Slider(value: $backgroundOpacity, in: 0.3...1.0).frame(width: 200)
                        Text(String(format: "%.0f%%", backgroundOpacity * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Text("Lower opacity makes the window more transparent — useful when placing it over a camera view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $textSize, in: 12...48).frame(width: 200)
                        Text("\(Int(textSize)) pt")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Tips") {
                Text("• Drag anywhere on the dark background to reposition the window.\n• Resize from the bottom-right corner; size is remembered between launches.\n• Spacebar starts/pauses. Escape pauses. Arrow keys nudge position manually.\n• Window is invisible to screen share by default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
    }
}

#Preview {
    SettingsView()
}
