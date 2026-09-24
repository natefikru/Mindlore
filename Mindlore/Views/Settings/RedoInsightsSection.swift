import SwiftData
import SwiftUI

// Settings, AI: run insights again on every entry, one at a time through the insights queue
// (owner, 2026-09-23). It asks first and names who reads them, since on OpenAI this sends the
// whole journal; while it runs the row counts and offers Stop.
struct RedoInsightsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(InsightsCoordinator.self) private var insights
    @State private var confirming: Int?

    private var usable: Bool {
        AIServices.insightsUsable(settings: settings, accounts: accounts)
    }

    var body: some View {
        Section {
            if let progress = insights.redo {
                HStack {
                    ProgressView()
                    Text("Redoing insights: \(progress.done) of \(progress.total)")
                        .accessibilityIdentifier("redoInsightsProgress")
                    Spacer()
                    Button("Stop") { insights.stopRedo(context: modelContext) }
                        .accessibilityIdentifier("stopRedoInsightsButton")
                }
            } else {
                Button("Redo insights for every entry") {
                    let count = Self.eligibleCount(in: modelContext)
                    confirming = count > 0 ? count : nil
                }
                .disabled(!usable)
                .accessibilityIdentifier("redoInsightsButton")
            }
        } footer: {
            Text(usable
                 ? "Every entry is read again, oldest first, one at a time. Names you added, merges, moods and kinds you picked, and loose ends you closed stay as they are."
                 : "Turn on insights in What AI does to redo them.")
        }
        .confirmationDialog(
            "Redo insights for every entry?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { count in
            Button("Redo \(Self.entries(count))") {
                Task { await insights.redoAll(context: modelContext) }
            }
            .accessibilityIdentifier("confirmRedoInsightsButton")
        } message: { count in
            Text(settings.insightsGenerator == .onDevice
                 ? "Runs on this iPhone, \(Self.entries(count)), one at a time."
                 : "Sends \(Self.entries(count)) to OpenAI, one at a time.")
        }
    }

    static func eligibleCount(in context: ModelContext) -> Int {
        ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? [])
            .filter(InsightsCoordinator.canRunAI).count
    }

    private static func entries(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }
}
