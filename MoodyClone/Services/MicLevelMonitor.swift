import AVFoundation
import Combine
import Foundation

@MainActor
final class MicLevelMonitor: ObservableObject {
    @Published var level: Float = 0
    @Published var isRunning: Bool = false
    @Published var permissionDenied: Bool = false

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
            return
        }
        permissionDenied = false

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let rms = Self.rms(buffer: buffer)
            Task { @MainActor in
                self?.level = rms
            }
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            print("MicLevelMonitor: engine.start failed: \(error)")
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channel = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Scale to roughly 0..1 for a quiet-to-loud talking voice.
        // 15x gain makes typical indoor speech register around 0.15–0.5.
        return min(1.0, max(0.0, rms * 15))
    }
}
