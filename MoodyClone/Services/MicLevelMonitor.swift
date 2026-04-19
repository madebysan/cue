import AVFoundation
import Combine
import Foundation

@MainActor
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

    private let engine = AVAudioEngine()

    func start() async {
        guard !isRunning else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let granted: Bool
        switch status {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            granted = false
        @unknown default:
            granted = false
        }

        guard granted else {
            permissionDenied = true
            lastStatusMessage = "permission denied"
            return
        }
        permissionDenied = false

        let input = engine.inputNode
        // prepare() ensures the engine is configured before we read the format.
        engine.prepare()

        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        channelCount = Int(format.channelCount)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastStatusMessage = "invalid input format (\(Int(format.sampleRate))Hz / \(format.channelCount)ch)"
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let raw = Self.rms(buffer: buffer)
            let scaled = min(1.0, max(0.0, raw * 15))
            Task { @MainActor in
                guard let self else { return }
                self.tapCallCount += 1
                self.lastRawRMS = raw
                self.level = scaled
            }
        }

        do {
            try engine.start()
            isRunning = true
            lastStatusMessage = "running @ \(Int(format.sampleRate))Hz / \(format.channelCount)ch"
        } catch {
            lastStatusMessage = "engine.start failed: \(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
        lastStatusMessage = "stopped"
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        // Prefer Float32 path (the typical inputNode format).
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
        // Fallback for Int16 buffers (some external USB mics).
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
