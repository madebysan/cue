import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("MoodyClone")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Phase 1 scaffold")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    ContentView()
}
