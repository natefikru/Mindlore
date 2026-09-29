import SwiftData
import SwiftUI

// The three screens a new install sees: what Mindlore is, a real ten-second recording that primes
// the microphone and speech permissions in context, and the daily reminder that primes
// notifications. Each after the first is skippable. AI is never asked about here: that consent
// alert (`AIConsent`) belongs to the Use AI switch and saving a key, both reachable through
// "I have an OpenAI key" on page one, which ends onboarding and opens Settings' AI screen directly.
struct OnboardingView: View {
    let onFinish: () -> Void
    let onAddKey: () -> Void
    let makeRecorder: () -> any AudioRecording
    let askRecordingPermissions: () async -> Void
    let reminder: DailyReminder

    @State private var page = 0

    var body: some View {
        ZStack {
            switch page {
            case 0:
                OnboardingWelcomePage(
                    onStart: { withAnimation(Motion.resolve(Motion.settle, reduceMotion: false)) { page = 1 } },
                    onAddKey: onAddKey
                )
            case 1:
                OnboardingRecordPage(
                    makeRecorder: makeRecorder,
                    askPermissions: askRecordingPermissions,
                    onContinue: { withAnimation(Motion.resolve(Motion.settle, reduceMotion: false)) { page = 2 } }
                )
            default:
                OnboardingReminderPage(reminder: reminder, onFinish: onFinish)
            }
        }
    }
}

private struct OnboardingWelcomePage: View {
    let onStart: () -> Void
    let onAddKey: () -> Void

    @Environment(SyncStatusMonitor.self) private var sync
    // Entries iCloud brings in while this is up. Only a new install or a new device sees this
    // screen, so the journal it loads is empty or arriving.
    @Query private var entries: [Entry]

    private var syncLine: WelcomeSyncLine? { WelcomeSyncLine.line(status: sync.status, entries: entries.count) }

    private let onDevice = FoundationModelsAvailability.isAvailable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    // The identifier sits on the title, not the screen: on an ancestor it would
                    // overwrite the buttons' own.
                    Text("Mindlore")
                        .font(.largeTitle.weight(.bold))
                        .accessibilityIdentifier("welcomeView")
                    Text("A journal that keeps track of what you write about.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 24) {
                    row("mic", "Speak or write", "Record an entry, type one, or photograph a page from a paper journal.")
                    row("circle.hexagongrid", "See how it connects", "The people, places, and open threads in your entries collect into a map you can search and correct.")
                    if let syncLine {
                        row(syncLine.symbol, syncLine.title, syncLine.detail, busy: syncLine.busy)
                            .accessibilityIdentifier("welcomeSync")
                    }
                    row("lock", "Private unless you say so", onDevice
                        ? "Entries are read by Apple's on-device model. Nothing goes to an AI service unless you add an OpenAI key."
                        : "Nothing goes to an AI service unless you add an OpenAI key, which also reads your entries for names, moods, and threads.")
                }
                .animation(Motion.resolve(Motion.settle, reduceMotion: false), value: syncLine)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onStart) {
                    Text(entries.isEmpty ? "Start" : "Open your journal")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.ember)
                .accessibilityIdentifier("welcomeStart")
                Button("I have an OpenAI key", action: onAddKey)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ember)
                    .accessibilityIdentifier("welcomeAddKey")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper.ignoresSafeArea())
    }

    private func row(_ symbol: String, _ title: String, _ detail: String, busy: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if busy {
                    ProgressView()
                } else {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(Palette.ember)
                }
            }
            .frame(width: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// A real recording, capped at ten seconds, that asks for the microphone and speech permissions
// the moment there's an obvious reason for them. The audio is always discarded: this page never
// creates an entry, so it can't accidentally become the user's first one.
private struct OnboardingRecordPage: View {
    let makeRecorder: () -> any AudioRecording
    let askPermissions: () async -> Void
    let onContinue: () -> Void

    private enum Phase: Equatable {
        case notStarted
        case recording
        case denied
        case finished
    }

    @State private var recorder: (any AudioRecording)?
    @State private var phase: Phase = .notStarted
    @State private var demoTask: Task<Void, Never>?

    static let demoDuration: TimeInterval = 10

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: skip)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboardingRecordSkip")
            }
            .padding()

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.ember)
                    .symbolEffect(.variableColor.iterative, isActive: phase == .recording)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("onboardingRecordPage")
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                switch phase {
                case .notStarted:
                    Button("Try it", action: startDemo)
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.ember)
                        .accessibilityIdentifier("onboardingRecordStart")
                case .recording:
                    Button("Stop", action: stopDemo)
                        .buttonStyle(.bordered)
                        .tint(Palette.ember)
                        .accessibilityIdentifier("onboardingRecordStart")
                case .denied:
                    Button("Continue", action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.ember)
                        .accessibilityIdentifier("onboardingRecordContinue")
                case .finished:
                    Button("Continue", action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.ember)
                        .accessibilityIdentifier("onboardingRecordContinue")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper.ignoresSafeArea())
        .onDisappear { demoTask?.cancel() }
    }

    private var title: String {
        switch phase {
        case .notStarted: "Try talking for a moment"
        case .recording: "Listening…"
        case .denied: "Microphone access is off"
        case .finished: "That's the idea"
        }
    }

    private var detail: String {
        switch phase {
        case .notStarted: "Mindlore turns what you say into a journal entry. This is just a try, nothing is saved."
        case .recording: "Say anything. It stops on its own in a few seconds, or tap Stop."
        case .denied: "Turn it on later in Settings whenever you're ready to record."
        case .finished: "That's what recording an entry feels like. Nothing from this try was kept."
        }
    }

    private func startDemo() {
        demoTask = Task {
            await askPermissions()
            let recorder = makeRecorder()
            self.recorder = recorder
            do {
                try await recorder.start()
            } catch {
                guard !Task.isCancelled else { return }
                phase = .denied
                DiagnosticsLog.shared.record("onboarding.recordDemo", ["outcome": .string("denied")])
                return
            }
            guard !Task.isCancelled else { return }
            phase = .recording
            try? await Task.sleep(for: .seconds(Self.demoDuration))
            guard !Task.isCancelled else { return }
            finishDemo()
        }
    }

    private func stopDemo() {
        demoTask?.cancel()
        finishDemo()
    }

    private func finishDemo() {
        let tried = recorder != nil
        recorder?.discard()
        recorder = nil
        phase = .finished
        if tried { DiagnosticsLog.shared.record("onboarding.recordDemo", ["outcome": .string("tried")]) }
    }

    private func skip() {
        let wasRecording = recorder != nil
        demoTask?.cancel()
        recorder?.discard()
        recorder = nil
        DiagnosticsLog.shared.record("onboarding.recordDemo", ["outcome": .string(wasRecording ? "abandoned" : "skipped")])
        onContinue()
    }
}

// The daily reminder, primed the same way: ask only once there's a reason, never at random.
private struct OnboardingReminderPage: View {
    let reminder: DailyReminder
    let onFinish: () -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var asking = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.ember)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Never miss a day")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("onboardingReminderPage")
                    Text("A quiet nudge once a day, only on days you haven't written yet. You can turn it off anytime in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button("Remind me", action: enable)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ember)
                    .disabled(asking)
                    .accessibilityIdentifier("onboardingReminderEnable")
                Button("Not now", action: skip)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboardingReminderSkip")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper.ignoresSafeArea())
    }

    private func enable() {
        asking = true
        Task {
            let allowed = await reminder.requestPermission()
            settings.reminderEnabled = allowed
            asking = false
            DiagnosticsLog.shared.record("onboarding.finished", ["remindersEnabled": .bool(allowed)])
            onFinish()
        }
    }

    private func skip() {
        DiagnosticsLog.shared.record("onboarding.finished", ["remindersEnabled": .bool(false)])
        onFinish()
    }
}

#Preview {
    OnboardingView(
        onFinish: {},
        onAddKey: {},
        makeRecorder: { UITestingRecorder() },
        askRecordingPermissions: {},
        reminder: DailyReminder()
    )
    .environment(SyncStatusMonitor(mirrors: false))
    .modelContainer(for: Entry.self, inMemory: true)
}
