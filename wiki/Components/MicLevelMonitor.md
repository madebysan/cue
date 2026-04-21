# MicLevelMonitor

## Purpose

Captures microphone audio as a stream of `CMSampleBuffer`s, forwards each buffer to any subscriber (the `SpeechTranscriber`), and also computes an RMS level for optional UI display. Handles permission flow and captures diagnostics.

## Location

`Cue/Services/MicLevelMonitor.swift` (152 lines)

## Interface

```swift
final class MicLevelMonitor: NSObject, ObservableObject,
                              AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var isRunning: Bool
    @Published var permissionDenied: Bool

    var onSampleBuffer: ((CMSampleBuffer) -> Void)?  // set by ContentView

    func start()
    func stop()
}
```

**Only `isRunning` and `permissionDenied` are `@Published`**. `level`, `sampleCount`, `lastRawRMS`, and `lastStatusMessage` are plain vars — making them `@Published` triggered 60 Hz SwiftUI re-renders when nothing in the view body consumed them. See [Design-Decisions.md DD-005](../Design-Decisions.md).

## Internal Design

### Why AVCaptureSession, not AVAudioEngine

The original implementation used `AVAudioEngine.inputNode.installTap(onBus:)`. On macOS 26 with Bluetooth microphones (AirPods, etc.), the tap callback **silently never fires** — no error, no crash, just silence. See [Design-Decisions.md DD-001](../Design-Decisions.md) and [Troubleshooting.md](../Troubleshooting.md).

`AVCaptureSession` is the CoreMedia-based capture API used by Camera, QuickTime, and most third-party mic-consuming apps. It's reliable on macOS 26, works with AirPods, is non-exclusive (coexists with Zoom/Meet), and triggers the orange mic-in-menu-bar indicator so the user knows capture is active.

### The capture graph

```
AVCaptureDevice.default(for: .audio)
        |
        v
AVCaptureDeviceInput
        |
        v
AVCaptureSession
        |
        v
AVCaptureAudioDataOutput
        |
        v
captureOutput(_:didOutput:from:) delegate callback
        |
        +-> onSampleBuffer?(sampleBuffer)   (forwarded to SpeechTranscriber)
        +-> rms(sampleBuffer) -> DispatchQueue.main.async { self.level = ... }
```

All delivered on the dedicated capture queue (`DispatchQueue(label: "cue.capture", qos: .userInitiated)`), with state mutations bounced to main.

### RMS calculation

`rms(sampleBuffer:)` pulls the raw audio bytes out of the buffer's `CMBlockBuffer`, reinterprets them as `Float` (AVCaptureAudioDataOutput delivers Float32 on macOS by default), and computes `sqrt(sum(sample^2) / N)`. Scaled by 15× so typical indoor speech registers around 0.15–0.5 on a 0–1 scale.

This RMS value is available as `level` for a volume meter display — but nothing in the UI currently consumes it. Kept for a future volume meter diagnostic panel.

## Permission Flow

`start()` checks `AVCaptureDevice.authorizationStatus(for: .audio)`:

- `.authorized` → immediately start the session
- `.notDetermined` → call `requestAccess(for:)` and start on callback
- `.denied` / `.restricted` → set `permissionDenied = true`, don't start

All permission logs go to `Logger.shared.log` so `~/Library/Logs/Cue/app.log` shows exactly why audio didn't start.

## Constraints

- **Must be running before `SpeechTranscriber` is useful.** Starting speech without a mic source = "No speech detected" error from SFSpeech.
- **Re-using the session instance across stop/start works.** Unlike `AVAudioEngine`, `AVCaptureSession` is well-behaved: stop → start again on the same instance is safe. We don't recreate it.
- **The session runs continuously during a user session.** Start on first play, stop on app quit (or explicit `stop()`). This keeps the orange dot stable and avoids re-prompting permission.
- **Mic switches (e.g. plugging in AirPods mid-session) require a session restart.** Default device is captured at `startSession()` time.

## Dependencies

- `AVFoundation` for `AVCaptureSession`, `AVCaptureDeviceInput`, `AVCaptureAudioDataOutput`
- `CoreMedia` for `CMBlockBuffer` / `CMSampleBuffer` pointer math in `rms`
- `Logger` for diagnostic output

## Related

- [SpeechTranscriber](SpeechTranscriber.md) — primary consumer of `onSampleBuffer`
- [Troubleshooting](../Troubleshooting.md) — what to check when audio isn't flowing
- [Design-Decisions](../Design-Decisions.md) — DD-001 (AVCaptureSession vs AVAudioEngine)
