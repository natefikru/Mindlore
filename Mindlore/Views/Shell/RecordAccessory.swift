import SwiftUI

// The tab bar's accessory while a recording runs. It keeps no state, because the system can draw
// it in both the expanded and the inline placement.
struct RecordAccessory: View {
    let session: RecordingSession
    let onDiscard: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if session.status != .idle {
            HStack(spacing: 12) {
                Button {
                    session.expand()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isCapturing ? Color.red : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(Duration.seconds(session.recorder?.elapsed ?? 0).formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                        if placement != .inline {
                            Capsule()
                                .fill(.red.opacity(0.8))
                                .frame(width: 4 + CGFloat(session.recorder?.level ?? 0) * 40, height: 4)
                                .animation(.linear(duration: 0.05), value: session.recorder?.level)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(isCapturing ? "Recording" : "Recording paused")
                .accessibilityHint("Shows the recorder")
                .accessibilityIdentifier("recordingAccessory")
                // Pause was only in a long-press menu nobody found. Where the bar is wide enough it
                // sits beside Finish; the inline bar keeps it in the menu below.
                if placement != .inline {
                    Button(isCapturing ? "Pause" : "Resume", systemImage: isCapturing ? "pause.fill" : "record.circle") {
                        session.togglePause()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!session.isRecording || session.isFinishing)
                    .accessibilityIdentifier("accessoryPauseButton")
                }
                Button("Finish", systemImage: "checkmark") {
                    Task { await session.finish() }
                }
                .labelStyle(.titleAndIcon)
                .disabled(!session.isRecording || session.isFinishing)
                .accessibilityIdentifier("accessoryFinishButton")
            }
            .padding(.horizontal)
            .contextMenu {
                if session.isRecording && !session.isFinishing {
                    Button(isCapturing ? "Pause" : "Resume", systemImage: isCapturing ? "pause" : "record.circle") {
                        session.togglePause()
                    }
                }
                Button("Discard Recording", systemImage: "trash", role: .destructive, action: onDiscard)
                    .disabled(session.isFinishing)
            }
        }
    }

    private var isCapturing: Bool {
        session.recorder?.state == .recording
    }
}
