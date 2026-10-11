import SwiftUI
import AVFoundation

/// Tap to record a quick note ("did legs: squats 3×8 at 135"), tap again to send.
/// The backend turns it into a structured log and remembers it.
@MainActor
final class VoiceRecorder: ObservableObject {
    enum State {
        case idle, recording, sending
        case done(AssistantService.ParsedLog)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var recorder: AVAudioRecorder?
    private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-note.wav")

    func toggle() async {
        if case .recording = state { await stopAndSend() } else { await start() }
    }

    private func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed("Microphone access is off. Turn it on in iPhone Settings → Habits.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // Mix so gym music keeps playing while you talk.
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            // 16 kHz mono PCM: small, and exactly what speech models want.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false
            ]
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.record(forDuration: 300) // the backend's ~5 minute cap
            self.recorder = recorder
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func stopAndSend() async {
        // A recorder that hit the 5-minute cap has already stopped; send that one.
        let accidentalTap = (recorder?.isRecording ?? false) && (recorder?.currentTime ?? 0) < 1
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard !accidentalTap else {
            state = .idle
            return
        }
        state = .sending
        do {
            state = .done(try await AssistantService.log(audioAt: fileURL))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct VoiceLogPanel: View {
    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await recorder.toggle() }
                } label: {
                    Label(buttonTitle, systemImage: buttonIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(fill: isRecording ? Palette.red : Palette.accent, textColor: .white))
                .disabled(isSending)

                result
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch recorder.state {
        case .idle:
            Text("Say what you did: \"Leg day, squats 3 by 8 at 135…\"")
                .font(.bodyRegular(12))
                .foregroundStyle(Palette.ink.opacity(0.6))
        case .recording:
            Text("Listening… tap again when you're done.")
                .font(.bodyMedium(13))
                .foregroundStyle(Palette.red)
        case .sending:
            HStack(spacing: 8) {
                ProgressView().tint(Palette.ink)
                Text("Logging it…").font(.bodyMedium(13)).foregroundStyle(Palette.ink)
            }
        case .done(let log):
            VStack(alignment: .leading, spacing: 4) {
                Text("Logged: \(log.title)")
                    .font(.heading(20))
                    .foregroundStyle(Palette.red)
                ForEach(Array(log.exercises.enumerated()), id: \.offset) { _, exercise in
                    Text("• \(exercise.line)")
                        .font(.bodyMedium(14))
                        .foregroundStyle(Palette.ink)
                }
                if log.exercises.isEmpty {
                    Text(log.transcript)
                        .font(.bodyRegular(13))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let mood = log.mood {
                    Text("Mood: \(mood)")
                        .font(.heading(13))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }
            }
        case .failed(let message):
            Text(message)
                .font(.bodyMedium(13))
                .foregroundStyle(Palette.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isRecording: Bool {
        if case .recording = recorder.state { return true }
        return false
    }

    private var isSending: Bool {
        if case .sending = recorder.state { return true }
        return false
    }

    private var buttonTitle: String {
        isRecording ? "Stop & Log" : isSending ? "Logging…" : "Voice Log"
    }

    private var buttonIcon: String {
        isRecording ? "stop.circle.fill" : "mic.fill"
    }
}
