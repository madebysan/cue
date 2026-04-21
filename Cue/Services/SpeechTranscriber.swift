import AVFoundation
import Foundation
import Speech

final class SpeechTranscriber: ObservableObject {
    // Only isRunning/authStatus are observed. Per-partial fields are plain vars.
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private(set) var lastRecognized: String = ""
    private(set) var lastError: String?
    private(set) var bufferCount: Int = 0

    /// Called every time new recognized text is available.
    /// Invoked on main queue.
    var onRecognized: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var internalBufferCount: Int = 0

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authStatus = status
                Logger.shared.log("SFSpeech auth status: \(status.rawValue) (0=notDetermined, 1=denied, 2=restricted, 3=authorized)")
                completion(status == .authorized)
            }
        }
    }

    func start() {
        guard !isRunning else { return }

        let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let r else {
            lastError = "SFSpeechRecognizer init returned nil — locale may be unsupported"
            Logger.shared.log("SFSpeechRecognizer init returned nil")
            return
        }
        Logger.shared.log("SFSpeechRecognizer: isAvailable=\(r.isAvailable), supportsOnDevice=\(r.supportsOnDeviceRecognition), locale=\(r.locale.identifier)")
        guard r.isAvailable else {
            lastError = "speech recognizer not available"
            Logger.shared.log("SFSpeechRecognizer unavailable")
            return
        }
        recognizer = r

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Try server-side first — on-device is more restrictive and sometimes silently fails.
        if r.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = false
            Logger.shared.log("on-device available but using server for reliability")
        }
        req.taskHint = .dictation
        request = req
        internalBufferCount = 0

        task = r.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Logger.shared.log("RECOGNIZED (isFinal=\(result.isFinal)): \"\(text)\"")
                DispatchQueue.main.async {
                    self.lastRecognized = text
                    self.onRecognized?(text)
                }
            }
            if let error {
                Logger.shared.log("SFSpeech task error: \(error.localizedDescription) — code=\((error as NSError).code)")
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                }
            }
        }

        isRunning = true
        Logger.shared.log("SpeechTranscriber started — task=\(task != nil)")
    }

    /// Feed a CMSampleBuffer straight from AVCaptureAudioDataOutput.
    /// Safe to call from the capture queue.
    func append(sampleBuffer: CMSampleBuffer) {
        guard let req = request else { return }
        req.appendAudioSampleBuffer(sampleBuffer)
        internalBufferCount += 1
        if internalBufferCount == 1 || internalBufferCount % 100 == 0 {
            let count = internalBufferCount
            Logger.shared.log("speech sample buffer #\(count) appended (numSamples=\(CMSampleBufferGetNumSamples(sampleBuffer)))")
            DispatchQueue.main.async { [weak self] in self?.bufferCount = count }
        }
    }

    func stop() {
        guard isRunning else { return }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        recognizer = nil
        isRunning = false
        Logger.shared.log("SpeechTranscriber stopped")
    }
}
