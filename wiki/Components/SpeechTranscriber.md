# SpeechTranscriber

## Purpose

Wraps `SFSpeechRecognizer` and `SFSpeechAudioBufferRecognitionRequest` into a simple start/stop/append interface. Accepts `CMSampleBuffer`s from `MicLevelMonitor`, streams recognized text back to `ContentView` via a closure.

## Location

`Cue/Services/SpeechTranscriber.swift` (119 lines)

## Interface

```swift
final class SpeechTranscriber: ObservableObject {
    @Published private(set) var isRunning: Bool
    @Published private(set) var authStatus: SFSpeechRecognizerAuthorizationStatus

    private(set) var lastRecognized: String
    private(set) var lastError: String?
    private(set) var bufferCount: Int

    var onRecognized: ((String) -> Void)?  // set by ContentView

    func requestAuthorization(_ completion: @escaping (Bool) -> Void)
    func start()
    func append(buffer: AVAudioPCMBuffer)         // legacy — unused now
    func append(sampleBuffer: CMSampleBuffer)     // primary path
    func stop()
}
```

## Internal Design

### Session lifecycle

- `start()` creates a new `SFSpeechRecognizer(locale: "en-US")` and a new `SFSpeechAudioBufferRecognitionRequest` on every call. Reusing across sessions caused subtle "partial results from previous session bleed into new one" bugs during development.
- `shouldReportPartialResults = true` — we want live updates as the user speaks, not just end-of-utterance finals.
- `taskHint = .dictation` — the speech model expects continuous reading (not single-command phrases).
- **`requiresOnDeviceRecognition = false`** — on-device is available on this hardware, but we've found server-based recognition more reliable during development. Swap to `true` for full privacy if recognition stalls are acceptable. See [Design-Decisions.md DD-003](../Design-Decisions.md).

### The recognition task callback

```swift
task = r.recognitionTask(with: req) { [weak self] result, error in
    if let result {
        let text = result.bestTranscription.formattedString
        DispatchQueue.main.async {
            self.lastRecognized = text
            self.onRecognized?(text)
        }
    }
    if let error {
        Logger.shared.log("SFSpeech task error: \(error.localizedDescription) — code=\((error as NSError).code)")
    }
}
```

On every partial result, the full cumulative transcript so far is passed to `onRecognized`. `TranscriptionMatcher.ingest(_:)` handles deduplication by only looking at the tail of what's new.

Errors are logged but don't crash the session. The most common error seen in development is `code 1110` ("No speech detected") — see [Troubleshooting.md](../Troubleshooting.md).

### Accepting audio

Two append methods exist:

- **`append(buffer: AVAudioPCMBuffer)`** — legacy, used when the mic came from `AVAudioEngine`. No longer called.
- **`append(sampleBuffer: CMSampleBuffer)`** — current primary path. Calls `SFSpeechAudioBufferRecognitionRequest.appendAudioSampleBuffer(_:)`, which accepts CoreMedia buffers directly. No format conversion.

Buffer count is logged at #1 and every 100th buffer to confirm audio is actually reaching the recognizer without spamming the log.

## Constraints

- **Siri & Dictation must be enabled system-wide.** If they're off, `SFSpeechRecognizer(locale:)` still initializes but `isAvailable` returns false, and `recognitionTask` silently does nothing. No user-visible error.
- **English-only right now** — locale hardcoded to `en-US`. Moving to `Locale.current` or a user setting is trivial (tracked in `backlog.md`).
- **Recognition lag varies** — typically 200–800 ms from speech to partial result. This is why the matcher needs the lookahead window; the spoken position is always a few words ahead of the recognized position.
- **Server-based recognition requires network.** Running on a plane? Set `requiresOnDeviceRecognition = true` first. This is not currently user-configurable.
- **Recognizer occasionally hallucinates.** The matcher handles this by requiring multi-word phrase matches above the similarity threshold — a hallucinated word won't match anything in the lookahead window.

## Dependencies

- `Speech` framework
- `AVFoundation` for `AVAudioPCMBuffer` signature on legacy append
- `Logger` for diagnostics

## Related

- [MicLevelMonitor](MicLevelMonitor.md) — source of `CMSampleBuffer`s
- [TranscriptionMatcher](TranscriptionMatcher.md) — primary consumer of `onRecognized`
- [Troubleshooting](../Troubleshooting.md) — "No speech detected" and other SFSpeech pitfalls
