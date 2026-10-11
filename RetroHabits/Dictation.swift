import Speech
import AVFoundation
import UIKit

/// Live speech-to-text with Apple's recognizer — on-device when the phone
/// supports it, so nothing is sent anywhere until you send the message.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var error: String?

    /// Called when listening ends by itself (you paused, or time ran out) with what was heard.
    var onAutoStop: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private var lastHeard = Date.distantPast
    private var watchdog: Task<Void, Never>?
    private var resignObserver: NSObjectProtocol?

    /// Stop after this long without new words once you've said something...
    private let pauseToStop: TimeInterval = 1.6
    /// ...or this long if nothing was said at all, and never listen longer than the cap.
    private let silenceToStop: TimeInterval = 8
    private let maxListen: TimeInterval = 60

    init() {
        // Never keep the mic on in the background.
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.stop() }
        }
    }
    /// A fresh engine per recording, released afterwards: a kept engine holds on to the
    /// microphone input, which leaves the mic looking active and can silence playback.
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        error = nil
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechAllowed, await AVAudioApplication.requestRecordPermission() else {
            error = "Allow Microphone and Speech Recognition for Habits in iPhone Settings."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition isn't available right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            let engine = AVAudioEngine()
            self.engine = engine
            Self.feed(engine.inputNode, into: request)
            engine.prepare()
            try engine.start()

            transcript = ""
            self.request = request
            isListening = true
            lastHeard = .now
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let done = error != nil || result?.isFinal == true
                Task { @MainActor in
                    // A cancelled recording reports late; ignore it so it can't end the next one.
                    guard let self, self.request === request else { return }
                    if let text, text != self.transcript { self.transcript = text; self.lastHeard = .now }
                    if done { self.autoStop() }
                }
            }
            watch(started: .now)
        } catch {
            self.error = error.localizedDescription
            finish()
        }
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stop() -> String {
        finish()
        return transcript
    }

    /// Ends listening when you pause, stay silent, or hit the time cap.
    private func watch(started: Date) {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.isListening else { return }
                let quiet = Date.now.timeIntervalSince(self.lastHeard)
                let paused = !self.transcript.isEmpty && quiet > self.pauseToStop
                let silent = self.transcript.isEmpty && quiet > self.silenceToStop
                if paused || silent || Date.now.timeIntervalSince(started) > self.maxListen {
                    self.autoStop()
                    return
                }
            }
        }
    }

    private func autoStop() {
        guard isListening else { return }
        finish()
        onAutoStop?(transcript)
    }

    private func finish() {
        watchdog?.cancel()
        watchdog = nil
        guard let engine else { isListening = false; return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The tap block runs on the audio thread, so it's built outside the main actor.
    private nonisolated static func feed(_ node: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }
}
