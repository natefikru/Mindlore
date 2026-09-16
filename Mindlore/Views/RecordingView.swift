import SwiftUI
import SwiftData

struct RecordingView: View {
    let onFinish: (Entry) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(RecordingIngestor.self) private var ingestor
    @Environment(TranscriptionCoordinator.self) private var transcription
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var recorder = AudioRecorder()
    @State private var levels: [Float] = Array(repeating: 0, count: 48)
    @State private var permissionDenied = false
    @State private var startFailed = false
    @State private var confirmingDiscard = false
    @State private var finishing = false
    @State private var liveSession: SpeechAnalyzerLiveSession?
    @State private var feedTask: Task<Void, Never>?

    let availability: LiveTranscriptionAvailability
    let locale: Locale

    init(availability: LiveTranscriptionAvailability = .standard, locale: Locale = .current, onFinish: @escaping (Entry) -> Void) {
        self.availability = availability
        self.locale = locale
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            Group {
                if permissionDenied {
                    ContentUnavailableView {
                        Label("Microphone access is off", systemImage: "mic.slash")
                    } description: {
                        Text("Mindlore needs the microphone to record entries.")
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
                    feedTask?.cancel()
                    feedTask = nil
                    liveSession = nil
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
        .onChange(of: recorder.audioGap) { _, gap in
            // Audio the transcriber never saw means its text covers less than the recording.
            if let gap { liveSession?.markUnhealthy(gap) }
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 32) {
            if let liveSession {
                LiveTranscriptText(session: liveSession)
            } else {
                Spacer()
            }
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
            await startLiveTranscription()
        } catch AudioRecorder.RecorderError.permissionDenied {
            permissionDenied = true
        } catch is CancellationError {
            return
        } catch {
            startFailed = true
        }
    }

    // Tier 1. Failing to start is not an error the user sees: the recording is already running and
    // the finished file gets text from the batch path instead.
    private func startLiveTranscription() async {
        let engine = settings.speechEngine
        let outcome = await availability.outcome(engine: engine, locale: locale)
        diagnosticsRecordAvailability(outcome)
        guard let buffers = recorder.buffers else { return }

        if case .unavailable(.assetNotInstalled) = outcome, let resolved = await availability.resolvedLocale(locale) {
            // Downloads for next time. Nothing here waits on it.
            Task.detached { await LiveTranscriptionAvailability.installAssets(for: resolved) }
        }
        guard outcome.isAvailable, let resolved = await availability.resolvedLocale(locale) else {
            recorder.stopBuffering()
            return
        }

        let session = SpeechAnalyzerLiveSession(locale: resolved)
        do {
            try await session.start()
        } catch {
            recorder.stopBuffering()
            return
        }
        liveSession = session
        if recorder.audioGap != nil { session.markUnhealthy("startedLate") }

        feedTask = Task {
            for await buffer in buffers {
                // Once the transcript can't be trusted it gets thrown away, so stop paying for it.
                guard session.isHealthy else {
                    recorder.stopBuffering()
                    return
                }
                session.feed(buffer)
            }
        }
    }

    private func diagnosticsRecordAvailability(_ outcome: LiveTranscriptionAvailability.Outcome) {
        DiagnosticsLog.shared.record("live.availability", [
            "engine": .string(settings.speechEngine.rawValue),
            "available": .bool(outcome.isAvailable),
            "reason": .string(outcome.reason?.rawValue ?? "none"),
        ])
    }

    private func togglePause() {
        if recorder.state == .recording { recorder.pause() } else { recorder.resume() }
    }

    private func finish() {
        finishing = true
        Task {
            // A failed stop or save leaves the file on disk; it becomes an entry on the next launch.
            let url = try? recorder.stop()
            // stop() ends the buffer stream. Wait for the feed to drain it before finishing the
            // session, or the last seconds of speech never reach the transcriber.
            await feedTask?.value
            feedTask = nil
            let liveText = await liveSession?.finish()
            liveSession = nil
            let entry: Entry? = if let url { await ingestor.ingest(url, context: modelContext, liveText: liveText) } else { nil }
            dismiss()
            if let entry { onFinish(entry) }
            await transcription.processQueue(context: modelContext)
        }
    }
}

// Committed text in full colour with the current guess trailing it, dimmed. The guess is rewritten
// constantly, so showing it in the same weight makes the whole paragraph look like it's flickering.
private struct LiveTranscriptText: View {
    let session: SpeechAnalyzerLiveSession

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
