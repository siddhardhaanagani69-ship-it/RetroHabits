import Speech
import AVFoundation

/// Live speech-to-text with Apple's recognizer — on-device when the phone
/// supports it, so nothing is sent anywhere until you send the message.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var error: String?

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        error = nil
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechAllowed, await AVAudioApplication.requestRecordPermission() else {
            error = "Allow Microphone and Speech Recognition for RetroHabits in iPhone Settings."
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
            Self.feed(engine.inputNode, into: request)
            engine.prepare()
            try engine.start()

            transcript = ""
            self.request = request
            isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let done = error != nil || result?.isFinal == true
                Task { @MainActor in
                    if let text { self?.transcript = text }
                    if done { self?.finish() }
                }
            }
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

    private func finish() {
        guard isListening || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
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
