import SwiftData
import SwiftUI

// The one screen a new install sees: what Mindlore is, what stays on the phone, and a way in.
// Deliberately not a tour or a questionnaire. Permissions are asked where they're needed (the
// microphone on the first recording), because that is when the reason is obvious.
struct WelcomeView: View {
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

#Preview {
    WelcomeView(onStart: {}, onAddKey: {})
        .environment(SyncStatusMonitor(mirrors: false))
        .modelContainer(for: Entry.self, inMemory: true)
}
