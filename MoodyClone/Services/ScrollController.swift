import Combine
import Foundation

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
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Logger.shared.log("ScrollController.start (speed=\(speed))")
    }

    func stop() {
        guard isScrolling else { return }
        isScrolling = false
        timer?.invalidate()
        timer = nil
        lastTick = nil
        Logger.shared.log("ScrollController.stop (offset=\(Int(offset)))")
    }

    func reset() {
        stop()
        offset = 0
        Logger.shared.log("ScrollController.reset")
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
