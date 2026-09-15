import SwiftUI
import SwiftData

struct RecordingView: View {
    let onFinish: (Entry) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(RecordingIngestor.self) private var ingestor
    @Environment(TranscriptionCoordinator.self) private var transcription
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var recorder = AudioRecorder()
    @State private var levels: [Float] = Array(repeating: 0, count: 48)
    @State private var permissionDenied = false
    @State private var startFailed = false
    @State private var confirmingDiscard = false
    @State private var finishing = false

    var body: some View {
        NavigationStack {
            Group {
                if permissionDenied {
                    ContentUnavailableView {
                        Label("Microphone access is off", systemImage: "mic.slash")
                    } description: {
                        Text("Mindlore needs the microphone to record entries. Recordings stay on your device.")
                    } actions: {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                } else if startFailed {
                    ContentUnavailableView("Couldn't start recording", systemImage: "exclamationmark.triangle", description: Text("Another app may be using the microphone. Try again in a moment."))
                } else {
                    recordingControls
                }
            }
            .navigationTitle("Voice Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if recorder.state == .idle { dismiss() } else { confirmingDiscard = true }
                    }
                    .disabled(finishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish)
                        .disabled(recorder.state == .idle || finishing)
                        .accessibilityIdentifier("finishRecordingButton")
                }
            }
            .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard Recording", role: .destructive) {
                    recorder.discard()
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled(recorder.state != .idle || finishing)
        .task { await startRecording() }
        .onChange(of: recorder.level) { _, level in
            levels.removeFirst()
            levels.append(level)
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 32) {
            Spacer()
            LevelBars(levels: levels)
                .frame(height: 96)
                .padding(.horizontal)
            Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
            Text(statusText)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: togglePause) {
                Image(systemName: recorder.state == .recording ? "pause.fill" : "record.circle")
                    .font(.system(size: 40))
                    .frame(width: 96, height: 96)
                    .background(recorder.state == .recording ? Color.secondary.opacity(0.2) : Color.red.opacity(0.9), in: Circle())
                    .foregroundStyle(recorder.state == .recording ? Color.primary : Color.white)
            }
            .accessibilityLabel(recorder.state == .recording ? "Pause" : "Resume")
            .disabled(recorder.state == .idle)
            .padding(.bottom, 48)
        }
    }

    private var statusText: String {
        switch recorder.state {
        case .idle: "Starting…"
        case .recording: "Recording"
        case .paused: "Paused"
        case .interrupted: "Paused by an interruption. Tap to keep recording."
        }
    }

    private func startRecording() async {
        do {
            try await recorder.start()
        } catch AudioRecorder.RecorderError.permissionDenied {
            permissionDenied = true
        } catch is CancellationError {
            return
        } catch {
            startFailed = true
        }
    }

    private func togglePause() {
        if recorder.state == .recording { recorder.pause() } else { recorder.resume() }
    }

    private func finish() {
        finishing = true
        Task {
            // A failed stop or save leaves the file on disk; it becomes an entry on the next launch.
            let url = try? recorder.stop()
            let entry: Entry? = if let url { await ingestor.ingest(url, context: modelContext) } else { nil }
            dismiss()
            if let entry { onFinish(entry) }
            await transcription.processQueue(context: modelContext)
        }
    }
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
