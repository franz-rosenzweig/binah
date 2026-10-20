import AVFoundation
import Foundation

/// A voice answer: AAC in an .m4a, mono, which the server decodes with PyAV (docs/API.md, Just a
/// Minute). It stops by itself at the limit, keeps the Mac awake while it records, and meters the
/// level for the bars on screen.
@MainActor @Observable
final class Recorder: NSObject {
    enum State: Equatable { case idle, recording, done }
    var state: State = .idle
    var elapsed: TimeInterval = 0
    /// The last few levels, 0…1, newest last.
    var levels: [Float] = Array(repeating: 0, count: 28)
    let limit: TimeInterval
    /// Called once, with the file's bytes, when the recording stops (by itself or by a press).
    var onFinish: ((Data, TimeInterval) -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var url: URL?

    init(limit: TimeInterval) { self.limit = limit }

    var left: TimeInterval { max(0, limit - elapsed) }

    /// Asks macOS once whether Binah may use the microphone.
    static func allowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("binah-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                       AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        let r = try AVAudioRecorder(url: u, settings: settings)
        r.isMeteringEnabled = true
        guard r.record() else { throw RecorderError.wouldNotStart }
        recorder = r
        url = u
        elapsed = 0
        state = .recording
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled],
                                                         reason: "Recording a voice answer")
        let started = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let r = self.recorder else { return }
                self.elapsed = Date().timeIntervalSince(started)
                r.updateMeters()
                let db = r.averagePower(forChannel: 0)            // -160 … 0
                let level = Float(max(0, min(1, (db + 50) / 50)))
                self.levels.removeFirst()
                self.levels.append(level)
                if self.elapsed >= self.limit { self.stop() }
            }
        }
    }

    /// Stops and hands over the recording.
    func stop() {
        guard state == .recording, let r = recorder else { return }
        let took = elapsed
        r.stop()
        cleanUp()
        state = .done
        if let url, let data = try? Data(contentsOf: url) {
            try? FileManager.default.removeItem(at: url)
            onFinish?(data, took)
        }
    }

    /// Stops and throws it away (leaving the game mid-answer).
    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        cleanUp()
        state = .idle
    }

    private func cleanUp() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}

enum RecorderError: LocalizedError {
    case wouldNotStart
    var errorDescription: String? { "The microphone didn't start. Check it in System Settings → Sound." }
}
