import AVFoundation
import Combine
import Foundation

final class MicLevelMonitor: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var level: Float = 0
    @Published var isRunning: Bool = false
    @Published var permissionDenied: Bool = false

    // Diagnostics
    @Published var sampleRate: Double = 0
    @Published var channelCount: Int = 0
    @Published var tapCallCount: Int = 0
    @Published var lastRawRMS: Float = 0
    @Published var lastStatusMessage: String = "not started"

    /// Called on the audio thread with every buffer from the input tap.
    /// SpeechTranscriber subscribes to this to feed the recognizer.
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    private var engine = AVAudioEngine()
    private var isStarting: Bool = false

    // AVCaptureSession is what actually wakes the mic hardware on macOS 26.
    // Without it, AVAudioEngine's input tap silently never fires.
    // We use it as the "activator" (its audio output also drives RMS + speech).
    private var captureSession: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "moody-clone.capture", qos: .userInitiated)

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
        engine = AVAudioEngine()

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Logger.shared.log("MicLevelMonitor.start — auth status=\(status.rawValue)")

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
            isStarting = false
        @unknown default:
            lastStatusMessage = "unknown permission status"
            isStarting = false
        }
    }

    private func startEngine() {
        // Activate the mic hardware via AVCaptureSession first. On macOS 26
        // AVAudioEngine's input tap won't fire unless something else has opened
        // the capture device.
        startCaptureSession()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        channelCount = Int(format.channelCount)

        Logger.shared.log("input format: \(Int(format.sampleRate))Hz / \(format.channelCount)ch")

        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastStatusMessage = "invalid input format"
            Logger.shared.log("ABORT: invalid input format")
            isStarting = false
            return
        }

        // macOS inputNode needs an output connection to pump audio.
        let mixer = engine.mainMixerNode
        mixer.outputVolume = 0
        engine.connect(input, to: mixer, format: format)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self else { return }
            // Forward the raw buffer to any subscriber (e.g. SpeechTranscriber) before we process.
            let cb = self.onAudioBuffer
            cb?(buffer, time)

            let raw = Self.rms(buffer: buffer)
            let scaled = min(1.0, max(0.0, raw * 15))
            // Log the first tap + subscriber presence so we can prove audio is flowing.
            DispatchQueue.main.async {
                if self.tapCallCount == 0 {
                    Logger.shared.log("FIRST TAP — frames=\(buffer.frameLength), raw=\(String(format: "%.5f", raw)), subscriber set=\(cb != nil)")
                }
                self.tapCallCount += 1
                self.lastRawRMS = raw
                self.level = scaled
                if self.tapCallCount % 120 == 0 {
                    Logger.shared.log("tap #\(self.tapCallCount) raw=\(String(format: "%.5f", raw)) subscriber=\(cb != nil)")
                }
            }
        }

        engine.prepare()

        do {
            try engine.start()
            isRunning = true
            isStarting = false
            lastStatusMessage = "running @ \(Int(format.sampleRate))Hz / \(format.channelCount)ch"
            Logger.shared.log("engine.start SUCCESS")
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
        captureSession?.stopRunning()
        captureSession = nil
        isRunning = false
        level = 0
        lastStatusMessage = "stopped"
        Logger.shared.log("MicLevelMonitor.stop — engine stopped, capture stopped")
    }

    private func startCaptureSession() {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            Logger.shared.log("AVCaptureDevice.default(.audio) returned nil")
            return
        }
        Logger.shared.log("AVCaptureDevice: \(device.localizedName)")

        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: captureQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.startRunning()
            captureSession = session
            Logger.shared.log("AVCaptureSession started (mic activator)")
        } catch {
            Logger.shared.log("AVCaptureSession setup failed: \(error)")
        }
    }

    // AVCaptureAudioDataOutputSampleBufferDelegate — just keeps the capture session
    // alive so AVAudioEngine's tap will fire. Samples here are discarded.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // intentionally empty — we only need the session running
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
        return 0
    }
}
