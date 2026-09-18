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
                HStack {
                    Text(verbatim: turn.text)
                        .foregroundStyle(turn.failureRaw == nil ? .primary : .secondary)
                        .accessibilityIdentifier(turn.failureRaw == nil ? "askAnswer" : "askAnswerNote")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                citations
                footer
            }
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var citations: some View {
        if !turn.citedEntryIDs.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(turn.citedEntryIDs.enumerated()), id: \.offset) { _, id in
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
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4), in: Capsule())
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
                Button("What was sent", action: showWhatWasSent)
                    .font(.caption2)
                    .accessibilityIdentifier("askWhatWasSent")
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
                    LabeledContent("Characters", value: turn.sentCharacters.formatted())
                } footer: {
                    Text("Only these entries were sent, inside delimiters, with your question.")
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
