import SwiftUI

// The full recorder, a view of RootView's RecordingSession. Closing it while recording minimizes
// it to the tab bar's accessory; the recording carries on.
struct RecordingView: View {
    @Environment(RecordingSession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            Group {
                switch session.status {
                case .permissionDenied:
                    ContentUnavailableView {
                        Label("Microphone access is off", systemImage: "mic.slash")
                    } description: {
                        Text("Mindlore needs the microphone to record entries.")
                    } actions: {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                case .startFailed:
                    ContentUnavailableView("Couldn't start recording", systemImage: "exclamationmark.triangle", description: Text("Another app may be using the microphone. Try again in a moment."))
                case .idle, .starting, .active:
                    recordingControls
                }
            }
            .navigationTitle("Voice Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if session.isRecording {
                        Button("Minimize", systemImage: "chevron.down") { session.minimize() }
                            .accessibilityIdentifier("minimizeRecordingButton")
                    } else {
                        Button("Close") { session.close() }
                            .accessibilityIdentifier("closeRecordingButton")
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if session.isRecording {
                        Button("Discard", systemImage: "trash", role: .destructive) { confirmingDiscard = true }
                            .disabled(session.isFinishing)
                            .accessibilityIdentifier("discardRecordingButton")
                    }
                    Button("Done") { Task { await session.finish() } }
                        .disabled(!session.isRecording || session.isFinishing)
                        .accessibilityIdentifier("finishRecordingButton")
                }
            }
            .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard Recording", role: .destructive) { session.discard() }
                    .accessibilityIdentifier("confirmDiscardRecordingButton")
            }
        }
        .interactiveDismissDisabled()
    }

    private var recordingControls: some View {
        VStack(spacing: 32) {
            if let liveSession = session.liveSession {
                LiveTranscriptText(session: liveSession)
            } else {
                Spacer()
            }
            LevelBars(levels: session.levels)
                .frame(height: 96)
                .padding(.horizontal)
            Text(Duration.seconds(session.recorder?.elapsed ?? 0).formatted(.time(pattern: .minuteSecond)))
                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
            Text(statusText)
                .foregroundStyle(.secondary)
            Spacer()
            Button { session.togglePause() } label: {
                Image(systemName: isCapturing ? "pause.fill" : "record.circle")
                    .font(.system(size: 40))
                    .frame(width: 96, height: 96)
                    .background(isCapturing ? Color.secondary.opacity(0.2) : Color.red.opacity(0.9), in: Circle())
                    .foregroundStyle(isCapturing ? Color.primary : Color.white)
            }
            .accessibilityLabel(isCapturing ? "Pause" : "Resume")
            .disabled(!session.isRecording || session.isFinishing || session.recorder?.isResuming == true)
            .padding(.bottom, 48)
        }
    }

    private var isCapturing: Bool {
        session.recorder?.state == .recording
    }

    private var statusText: String {
        if session.isFinishing { return "Saving…" }
        guard let recorder = session.recorder, session.isRecording else { return "Starting…" }
        if recorder.isResuming {
            return "Resuming…"
        }
        if recorder.resumeFailed {
            return "The microphone isn't free yet. Tap again in a moment."
        }
        return switch recorder.state {
        case .idle: "Starting…"
        case .recording: "Recording"
        case .paused: "Paused"
        case .interrupted: "Paused by an interruption. Tap to keep recording."
        }
    }
}

// Committed text in full colour with the current guess trailing it, dimmed. The guess is rewritten
// constantly, so showing it in the same weight makes the whole paragraph look like it's flickering.
private struct LiveTranscriptText: View {
    let session: any LiveTranscriptionSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    Text(session.finalizedText)
                    + Text(session.finalizedText.isEmpty || session.volatileText.isEmpty ? "" : " ")
                    + Text(session.volatileText).foregroundStyle(.secondary)
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .id(Self.bottomID)
            }
            .onChange(of: session.finalizedText) { _, _ in
                withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("liveTranscript")
        .accessibilityLabel("Live transcript")
        .accessibilityValue(session.displayText)
    }

    private static let bottomID = "liveTranscriptBottom"
}

private struct LevelBars: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, CGFloat(levels[index]) * 96))
            }
        }
        .animation(.linear(duration: 0.05), value: levels)
        .accessibilityHidden(true)
    }
}
