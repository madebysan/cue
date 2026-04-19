import AVFoundation
import Combine
import Foundation

final class MicLevelMonitor: ObservableObject {
    @Published var level: Float = 0
    @Published var isRunning: Bool = false
    @Published var permissionDenied: Bool = false

    // Diagnostics (surfaced in the UI for debugging)
    @Published var sampleRate: Double = 0
    @Published var channelCount: Int = 0
    @Published var tapCallCount: Int = 0
    @Published var lastRawRMS: Float = 0
    @Published var lastStatusMessage: String = "not started"

    // Recreated on every start(). AVAudioEngine is unstable across stop/start on macOS —
    // reusing the same instance crashes on the second start().
    private var engine = AVAudioEngine()
    private var isStarting: Bool = false

    func start() {
        guard !isRunning else {
            Logger.shared.log("MicLevelMonitor.start called but already running")
            return
        }
        guard !isStarting else {
            Logger.shared.log("MicLevelMonitor.start called while a start is already in flight — ignoring")
            return
        }
        isStarting = true

        // Fresh engine every start — AVAudioEngine is unstable across stop/start on macOS.
        engine = AVAudioEngine()

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Logger.shared.log("MicLevelMonitor.start — auth status=\(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        switch status {
        case .authorized:
            startEngine()
        case .notDetermined:
            Logger.shared.log("requesting mic permission…")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    Logger.shared.log("mic permission response: granted=\(granted)")
                    if granted {
                        self.permissionDenied = false
                        self.startEngine()
                    } else {
                        self.permissionDenied = true
                        self.lastStatusMessage = "permission denied"
                        self.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
            lastStatusMessage = "permission denied — enable in System Settings → Privacy & Security → Microphone"
            Logger.shared.log("mic permission previously denied/restricted — cannot start")
            isStarting = false
        @unknown default:
            lastStatusMessage = "unknown permission status"
            Logger.shared.log("unknown mic permission status")
            isStarting = false
        }
    }

    private func startEngine() {
        let input = engine.inputNode
        engine.prepare()

        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        channelCount = Int(format.channelCount)

        Logger.shared.log("engine.prepare done — input format: \(Int(format.sampleRate))Hz / \(format.channelCount)ch, commonFormat=\(format.commonFormat.rawValue) (1=float32, 2=float64, 3=int16, 4=int32)")

        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastStatusMessage = "invalid input format (\(Int(format.sampleRate))Hz / \(format.channelCount)ch)"
            Logger.shared.log("ABORT: invalid input format — no tap installed")
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let raw = Self.rms(buffer: buffer)
            let scaled = min(1.0, max(0.0, raw * 15))
            DispatchQueue.main.async {
                guard let self else { return }
                self.tapCallCount += 1
                self.lastRawRMS = raw
                self.level = scaled
                // Log every 60th tap (~1/sec at 60fps) so the file doesn't explode.
                if self.tapCallCount % 60 == 0 {
                    Logger.shared.log("tap #\(self.tapCallCount) — raw RMS=\(String(format: "%.5f", raw)), scaled=\(String(format: "%.3f", scaled))")
                }
            }
        }

        do {
            try engine.start()
            isRunning = true
            isStarting = false
            lastStatusMessage = "running @ \(Int(format.sampleRate))Hz / \(format.channelCount)ch"
            Logger.shared.log("engine.start SUCCESS — tap installed on bus 0")
        } catch {
            lastStatusMessage = "engine.start failed: \(error.localizedDescription)"
            isRunning = false
            isStarting = false
            Logger.shared.log("engine.start FAILED: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
        lastStatusMessage = "stopped"
        Logger.shared.log("MicLevelMonitor.stop — engine stopped, tap removed")
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        if let channelData = buffer.floatChannelData {
            let channel = channelData.pointee
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return 0 }
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channel[i]
                sum += sample * sample
            }
            return sqrt(sum / Float(frameLength))
        }
        if let int16Data = buffer.int16ChannelData {
            let channel = int16Data.pointee
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return 0 }
            var sum: Float = 0
            let scale: Float = 1.0 / Float(Int16.max)
            for i in 0..<frameLength {
                let sample = Float(channel[i]) * scale
                sum += sample * sample
            }
            return sqrt(sum / Float(frameLength))
        }
        return 0
    }
}
