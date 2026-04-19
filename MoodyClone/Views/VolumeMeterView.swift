import SwiftUI

struct VolumeMeterView: View {
    let level: Float
    let threshold: Float
    var active: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(active && level > threshold ? Color.green : Color.secondary.opacity(0.8))
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.easeOut(duration: 0.08), value: level)
                Rectangle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 2)
                    .offset(x: geo.size.width * CGFloat(threshold) - 1)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 20) {
        VolumeMeterView(level: 0.1, threshold: 0.15)
        VolumeMeterView(level: 0.3, threshold: 0.15)
        VolumeMeterView(level: 0.7, threshold: 0.15)
    }
    .padding()
    .frame(width: 300)
}
