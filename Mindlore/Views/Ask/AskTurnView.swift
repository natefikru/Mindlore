import SwiftData
import SwiftUI

// Resolving a cited or sent entry id to something a chip can show. An entry deleted since the
// answer leaves its id behind, which reads as "Entry deleted" and can't be tapped.
enum AskEntryRefs {
    struct Ref: Equatable, Identifiable {
        let id: UUID
        let title: String
        let date: Date
        let isDayOnly: Bool
    }

    static func entry(_ id: UUID, in context: ModelContext) -> Entry? {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        return ((try? context.fetch(descriptor)) ?? []).first { !$0.isDeleted }
    }

    static func refs(_ ids: [UUID], in context: ModelContext) -> [UUID: Ref] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Set(ids)
        let entries = ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { wanted.contains($0.id) }))) ?? [])
            .filter { !$0.isDeleted }
        return Dictionary(uniqueKeysWithValues: entries.map {
            ($0.id, Ref(id: $0.id, title: JournalSearch.displayTitle(for: $0), date: $0.entryDate, isDayOnly: $0.entryDateIsDayOnly))
        })
    }

    static func dateText(_ date: Date, dayOnly: Bool) -> String {
        dayOnly
            ? date.formatted(.dateTime.weekday(.abbreviated).month().day().year())
            : date.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
    }
}

// One turn: the question on the right, the answer on the left with its citations and the line
// saying what went out. Answers are always Text(verbatim:), so nothing an entry contains can
// become a link or markdown.
struct AskTurnView: View {
    let turn: AskTurn
    // The conversation's own map, so a chip is labelled with the handle the answer cited.
    let handles: [String: UUID]
    let openEntry: (UUID) -> Void
    let showWhatWasSent: () -> Void
    let retry: () -> Void
    let isLast: Bool

    @Environment(\.modelContext) private var modelContext
    // Looked up once per turn rather than on every draw, since a conversation redraws whenever
    // an answer streams in or the keyboard moves.
    @State private var refs: [UUID: AskEntryRefs.Ref] = [:]
    @State private var showsAllCitations = false
    @State private var pulse = false

    var body: some View {
        content
            .task(id: turn.citedEntryIDs) {
                refs = AskEntryRefs.refs(turn.citedEntryIDs, in: modelContext)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(verbatim: turn.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("askQuestion")
            }
            .padding(.horizontal)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                // Nothing has arrived yet: the spinner under the conversation is saying so, and
                // an empty bubble would only say it twice.
                if !(turn.isStreaming && turn.text.isEmpty) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(verbatim: turn.text)
                            .foregroundStyle(turn.failureRaw == nil ? .primary : .secondary)
                            .accessibilityIdentifier(turn.failureRaw == nil ? "askAnswer" : "askAnswerNote")
                        if turn.isStreaming { caret }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                citations
                footer
            }
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    // Something alive at the end of the sentence, so a pause between deltas reads as thinking
    // rather than as finished.
    private var caret: some View {
        Text(verbatim: "\u{258B}")
            .foregroundStyle(.tertiary)
            .opacity(pulse ? 0.2 : 1)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }

    // How many chips a quiet answer can carry. A broad question can now cite thirty-three days,
    // because the digest tier made every matched entry citable where fifteen were before, and
    // thirty-three chips under one paragraph is the bookkeeping this phase took out of the prose
    // arriving again in another form.
    static let visibleCitations = 6

    private var shownCitations: [UUID] {
        showsAllCitations ? turn.citedEntryIDs : Array(turn.citedEntryIDs.prefix(Self.visibleCitations))
    }

    @ViewBuilder
    private var citations: some View {
        if !turn.citedEntryIDs.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(shownCitations.enumerated()), id: \.offset) { _, id in
                        let handle = handles.first { $0.value == id }?.key ?? "E?"
                        if let ref = refs[id] {
                            Button { openEntry(id) } label: {
                                chip(title: ref.title, subtitle: AskEntryRefs.dateText(ref.date, dayOnly: ref.isDayOnly))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("askCitation-\(handle)")
                        } else {
                            chip(title: "Entry deleted", subtitle: "")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("askCitation-\(handle)")
                        }
                    }
                    if !showsAllCitations, turn.citedEntryIDs.count > Self.visibleCitations {
                        Button("\(turn.citedEntryIDs.count - Self.visibleCitations) more") {
                            withAnimation(.snappy(duration: 0.2)) { showsAllCitations = true }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("askMoreCitations")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // Quiet on purpose. The answer says nothing about where it came from any more, so the chips
    // are the whole of it: there to be tapped when someone wants the day itself, not a receipt
    // reading itself out under every answer.
    private func chip(title: String, subtitle: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
                .font(.caption2)
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.25), in: Capsule())
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            if !turn.providerLabel.isEmpty {
                Text(providerName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !turn.sentEntryIDs.isEmpty {
                // An icon, not a sentence. The receipt still exists, one tap away, without a line
                // of bookkeeping under every answer.
                Button("What was sent", systemImage: "info.circle", action: showWhatWasSent)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("askWhatWasSent")
            }
            if turn.wasStopped {
                Text("Stopped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("askStopped")
            }
            if turn.canRetry, isLast {
                Button("Retry", action: retry)
                    .font(.caption2)
                    .accessibilityIdentifier("askRetry")
            }
        }
    }

    private var providerName: String {
        turn.providerLabel == FoundationModelsTextGenerator.label
            ? "Answered on this iPhone"
            : "Answered by \(turn.providerLabel.split(separator: ":").last.map(String.init) ?? turn.providerLabel)"
    }
}

// What left the phone for one answer: how many entries, how many characters, and which entries.
struct AskWhatWasSentView: View {
    let turn: AskTurn
    let openEntry: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Entries", value: turn.sentEntryIDs.count.formatted())
                    // Most of a broad question's entries go as a single line. "Entries: 170" on its
                    // own would say the whole journal was read out, which is not what happened.
                    if turn.digestEntryCount > 0 {
                        LabeledContent("Read in full", value: turn.fullEntryCount.formatted())
                            .accessibilityIdentifier("askWhatWasSentFull")
                        LabeledContent("Read as one line", value: turn.digestEntryCount.formatted())
                            .accessibilityIdentifier("askWhatWasSentDigests")
                    }
                    // What the answer was written from, against what it could have been written
                    // from. Without this the count reads as the whole answer to the question.
                    if turn.wasCut {
                        LabeledContent("Matching entries", value: turn.matchedCount.formatted())
                            .accessibilityIdentifier("askWhatWasSentMatched")
                    }
                    if turn.rollupMonthCount > 0 {
                        LabeledContent("Monthly summaries", value: "^[\(turn.rollupMonthCount) month](inflect: true)")
                            .accessibilityIdentifier("askWhatWasSentSummaries")
                    }
                    LabeledContent("Characters", value: turn.sentCharacters.formatted())
                } footer: {
                    Text(turn.providerLabel == FoundationModelsTextGenerator.label
                        ? "Only these entries were read, and nothing left this iPhone."
                        : "Only these entries were sent, inside delimiters, with your question.")
                }
                Section("Entries") {
                    let refs = AskEntryRefs.refs(turn.sentEntryIDs, in: modelContext)
                    ForEach(turn.sentEntryIDs, id: \.self) { id in
                        if let ref = refs[id] {
                            Button {
                                dismiss()
                                openEntry(id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: ref.title)
                                    Text(AskEntryRefs.dateText(ref.date, dayOnly: ref.isDayOnly))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Entry deleted").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("What was sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("askWhatWasSentSheet")
    }
}
