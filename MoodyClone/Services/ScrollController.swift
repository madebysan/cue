import Combine
import Foundation

@MainActor
final class ScrollController: ObservableObject {
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var isScrolling: Bool = false

    var speed: Double = 80

    private var timer: Timer?
    private var lastTick: Date?

    func start() {
        guard !isScrolling else { return }
        isScrolling = true
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        guard isScrolling else { return }
        isScrolling = false
        timer?.invalidate()
        timer = nil
        lastTick = nil
    }

    func reset() {
        stop()
        offset = 0
    }

    private func tick() {
        guard let last = lastTick else { return }
        let now = Date()
        let dt = now.timeIntervalSince(last)
        lastTick = now
        guard dt > 0, dt < 0.25 else { return }
        offset += CGFloat(speed * dt)
    }

    deinit {
        timer?.invalidate()
    }
}
