import AVFoundation
import SwiftUI

struct AudioPlayerView: View {
    let data: Data
    let duration: Double?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var failed = false
    @State private var position: TimeInterval = 0
    // While the scrubber is held, the playhead follows the finger rather than the player.
    @State private var scrubbing = false

    private var length: TimeInterval {
        player?.duration ?? duration ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button { skip(by: -PlaybackPosition.skipSeconds) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title3)
                }
                .accessibilityLabel("Back 10 seconds")
                .accessibilityIdentifier("skipBackButton")

                Button(action: toggle) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                }
                .accessibilityLabel(isPlaying ? "Pause recording" : "Play recording")

                Button { skip(by: PlaybackPosition.skipSeconds) } label: {
                    Image(systemName: "goforward.10")
                        .font(.title3)
                }
                .accessibilityLabel("Forward 10 seconds")
                .accessibilityIdentifier("skipForwardButton")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording")
                        .font(.subheadline.weight(.medium))
                    Text(failed ? "This recording can't be played." : timeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .buttonStyle(.borderless)

            if !failed, length > 0 {
                Slider(value: $position, in: 0...length) { editing in
                    scrubbing = editing
                    if !editing { seek(to: position) }
                }
                .accessibilityLabel("Playback position")
                .accessibilityValue(PlaybackPosition.label(position))
                .accessibilityIdentifier("playbackScrubber")
            }
        }
        .disabled(failed)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .task { loadPlayer() }
        .task(id: isPlaying) {
            while isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let player else { break }
                if !scrubbing { position = player.currentTime }
                if !player.isPlaying {
                    isPlaying = false
                    // A finished player rewinds itself; the playhead goes with it.
                    position = player.currentTime
                    Self.releaseSession()
                }
            }
        }
        .onDisappear {
            let wasPlaying = isPlaying
            player?.stop()
            isPlaying = false
            if wasPlaying { Self.releaseSession() }
        }
    }

    private var timeText: String {
        guard length > 0 else { return "Length unknown" }
        return "\(PlaybackPosition.label(position)) / \(PlaybackPosition.label(length))"
    }

    private func loadPlayer() {
        guard player == nil else { return }
        do {
            player = try AVAudioPlayer(data: data)
            player?.prepareToPlay()
        } catch {
            failed = true
        }
    }

    private func toggle() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            Self.releaseSession()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            loadPlayer()
            isPlaying = player?.play() ?? false
        } catch {
            failed = true
        }
    }

    // Playback holds the audio session only while it plays. Left active, it kept other audio
    // (another app, a keyboard's voice typing) waiting on this app after the recording stopped.
    // Only the player's own session: a recording in the accessory holds a `.record` one.
    private static func releaseSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category == .playback else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func skip(by seconds: TimeInterval) {
        seek(to: PlaybackPosition.skipped(from: player?.currentTime ?? position, by: seconds, duration: length))
    }

    private func seek(to time: TimeInterval) {
        loadPlayer()
        guard let player else { return }
        player.currentTime = time
        position = time
    }
}

// Where the playhead lands and how it reads. Kept out of the view so the edges are testable.
nonisolated enum PlaybackPosition {
    static let skipSeconds: TimeInterval = 10

    // A skip never leaves the recording: back from the first seconds lands at the start, forward
    // from the last seconds lands at the end.
    static func skipped(from time: TimeInterval, by seconds: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(0, time + seconds), max(0, duration))
    }

    static func label(_ time: TimeInterval) -> String {
        let seconds = time.isFinite ? max(0, time) : 0
        return Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}
