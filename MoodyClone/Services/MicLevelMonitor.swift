import AVFoundation
import Combine
import Foundation

final class MicLevelMonitor: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
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

    // Secondary capture path — AVCaptureSession is CoreMedia-based and uses a
    // different plumbing than AVAudioEngine. Running both in parallel during
    // debug so whichever one actually pumps samples drives the UI.
    private var captureSession: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "moody-clone.capture", qos: .userInitiated)
    @Published var captureCallCount: Int = 0

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
        startCaptureSession()  // parallel AVCaptureSession path for diagnostics
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        channelCount = Int(format.channelCount)

        Logger.shared.log("input format: \(Int(format.sampleRate))Hz / \(format.channelCount)ch, commonFormat=\(format.commonFormat.rawValue) (1=float32, 2=float64, 3=int16, 4=int32)")

        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastStatusMessage = "invalid input format (\(Int(format.sampleRate))Hz / \(format.channelCount)ch)"
            Logger.shared.log("ABORT: invalid input format — no tap installed")
            isStarting = false
            return
        }

        // Connect input → mainMixer → (implicit output). On macOS the inputNode
        // doesn't pump audio unless it's connected somewhere. Muting the mixer
        // avoids speaker feedback.
        let mixer = engine.mainMixerNode
        mixer.outputVolume = 0
        engine.connect(input, to: mixer, format: format)
        Logger.shared.log("connected input → mainMixer (muted)")

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let raw = Self.rms(buffer: buffer)
            let scaled = min(1.0, max(0.0, raw * 15))
            // Log the very first tap firing directly from the audio thread so we
            // confirm callbacks are running at all.
            if let self, self.tapCallCount == 0 {
                Logger.shared.log("FIRST TAP FIRED — frameLength=\(buffer.frameLength), raw=\(String(format: "%.5f", raw))")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.tapCallCount += 1
                self.lastRawRMS = raw
                self.level = scaled
                if self.tapCallCount % 60 == 0 {
                    Logger.shared.log("tap #\(self.tapCallCount) — raw=\(String(format: "%.5f", raw)), scaled=\(String(format: "%.3f", scaled))")
                }
            }
        }
        Logger.shared.log("tap installed on bus 0")

        engine.prepare()
        Logger.shared.log("engine.prepare complete")

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
        Logger.shared.log("MicLevelMonitor.stop — engine stopped, tap removed, captureSession stopped")
    }

    private func startCaptureSession() {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            Logger.shared.log("AVCaptureDevice.default(.audio) returned nil")
            return
        }
        Logger.shared.log("AVCaptureDevice: \(device.localizedName) (\(device.uniqueID))")

        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                Logger.shared.log("captureSession cannot add input")
                return
            }
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: captureQueue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                Logger.shared.log("captureSession cannot add output")
                return
            }
            session.startRunning()
            captureSession = session
            Logger.shared.log("AVCaptureSession started")
        } catch {
            Logger.shared.log("AVCaptureSession setup failed: \(error)")
        }
    }

    // AVCaptureAudioDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let count: Int = {
            var c = 0
            DispatchQueue.main.sync {
                self.captureCallCount += 1
                c = self.captureCallCount
            }
            return c
        }()
        if count == 1 || count % 60 == 0 {
            Logger.shared.log("AVCapture sample #\(count) — numSamples=\(CMSampleBufferGetNumSamples(sampleBuffer))")
        }
        // Extract RMS from sample buffer for the level meter.
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<CChar>? = nil
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard let ptr = dataPointer, totalLength > 0 else { return }

        // Assume Float32 mono (AVCaptureAudioDataOutput default on macOS).
        let floatCount = totalLength / MemoryLayout<Float>.size
        let floatPtr = ptr.withMemoryRebound(to: Float.self, capacity: floatCount) { $0 }
        var sum: Float = 0
        for i in 0..<floatCount {
            let sample = floatPtr[i]
            sum += sample * sample
        }
        let raw = sqrt(sum / Float(floatCount))
        let scaled = min(1.0, max(0.0, raw * 15))
        DispatchQueue.main.async {
            self.lastRawRMS = raw
            self.level = scaled
        }
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
