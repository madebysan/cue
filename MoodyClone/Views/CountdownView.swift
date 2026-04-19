import SwiftUI

struct CountdownView: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 140, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
            .id(value)
    }
}

#Preview {
    CountdownView(value: 3)
        .frame(width: 400, height: 300)
}
