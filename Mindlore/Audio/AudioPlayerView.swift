import AVFoundation
import SwiftUI

struct AudioPlayerView: View {
    let data: Data
    let duration: Double?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var failed = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
            }
            .accessibilityLabel(isPlaying ? "Pause recording" : "Play recording")
            .disabled(failed)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recording")
                    .font(.subheadline.weight(.medium))
                Text(failed ? "This recording can't be played." : durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .task(id: isPlaying) {
            while isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if player?.isPlaying != true { isPlaying = false }
            }
        }
        .onDisappear {
            player?.stop()
            isPlaying = false
        }
    }

    private var durationText: String {
        guard let duration else { return "Length unknown" }
        return Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))
    }

    private func toggle() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        do {
            if player == nil {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                player = try AVAudioPlayer(data: data)
            }
            try AVAudioSession.sharedInstance().setActive(true)
            isPlaying = player?.play() ?? false
        } catch {
            failed = true
        }
    }
}
