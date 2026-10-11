import SwiftUI
import AVFoundation

/// Plays today's spoken briefing. Tap again to stop.
@MainActor
final class BriefingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum State { case idle, loading, playing }

    @Published private(set) var state: State = .idle
    private var player: AVAudioPlayer?

    func toggle() async {
        switch state {
        case .playing:
            stop()
        case .loading:
            break
        case .idle:
            state = .loading
            do {
                let data = try await AssistantService.briefingAudio()
                // Duck music rather than stop it, like a navigation prompt.
                try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.play()
                self.player = player
                state = .playing
            } catch {
                state = .idle
            }
        }
    }

    private func stop() {
        player?.stop()
        player = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

struct BriefingButton: View {
    @StateObject private var player = BriefingPlayer()

    var body: some View {
        Button {
            Task { await player.toggle() }
        } label: {
            switch player.state {
            case .loading: ProgressView().tint(Palette.ink)
            case .playing: Image(systemName: "stop.fill").font(.system(size: 16, weight: .black))
            case .idle: Image(systemName: "speaker.wave.2.fill").font(.system(size: 16, weight: .black))
            }
        }
        .buttonStyle(FilledButtonStyle(fill: player.state == .playing ? Palette.red : Palette.fill,
                                      textColor: player.state == .playing ? .white : Palette.blue))
        .accessibilityLabel(player.state == .playing ? "Stop briefing" : "Play today's briefing")
    }
}
