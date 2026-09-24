import SwiftData
import SwiftUI

// Data cleanup, moved out of the drawer's way: the review questions one at a time ("which one?"
// first, then "same?"), then the names the user hid. Skips are for the session, shared with the
// drawer so its count agrees.
struct TidyUpView: View {
    @Binding var skipped: Set<String>
    let hidden: [EntitySearch.Row]
    let open: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GraphServices.self) private var graph
    @Environment(EntrySaver.self) private var saver
    @State private var questions: [ReviewQueue.Question] = []
    @State private var names: [UUID: String] = [:]
    @State private var questionDate: Date?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let question = questions.first {
                        ReviewCard(question: question, entryDate: questionDate, names: names, answer: answer)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    } else {
                        Text("Nothing to check.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("tidyUpNothing")
                    }
                } header: {
                    Text(questions.count > 1 ? "\(questions.count) to check" : "To check")
                }
                if !hidden.isEmpty {
                    Section("Hidden") {
                        ForEach(hidden) { row in
                            Button {
                                dismiss()
                                open(row.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: row.kind.symbol)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    Text(row.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mindHiddenRow-\(row.name)")
                        }
                    }
                    .accessibilityIdentifier("mindHiddenSection")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .navigationTitle("Tidy up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tidyUpDone")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: graph.revision) { refresh() }
        .accessibilityIdentifier("mindTidyUpSheet")
    }

    private func answer(_ question: ReviewQueue.Question, _ answer: GraphServices.ReviewAnswer) {
        if answer == .skip {
            skipped.insert(question.id)
        }
        saver.flush()
        graph.answer(question, with: answer, in: modelContext)
        // A real answer bumps graph.revision, which refreshes; a skip doesn't.
        if answer == .skip {
            refresh()
        }
    }

    private func refresh() {
        questions = ReviewQueue.questions(
            suggestions: graph.editor.suggestions(in: modelContext),
            unsure: graph.unsureLinks(in: modelContext),
            skipped: skipped
        )
        let entities = ((try? modelContext.fetch(FetchDescriptor<Entity>())) ?? []).filter { !$0.isDeleted }
        names = Dictionary(entities.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        if case .whichOne(let unsure) = questions.first {
            let entryID = unsure.mention.entryID
            var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
            descriptor.fetchLimit = 1
            questionDate = (try? modelContext.fetch(descriptor))?.first?.entryDate
        } else {
            questionDate = nil
        }
    }
}

// One question at a time from the review queue, answered with one tap.
struct ReviewCard: View {
    let question: ReviewQueue.Question
    let entryDate: Date?
    let names: [UUID: String]
    let answer: (ReviewQueue.Question, GraphServices.ReviewAnswer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch question {
            case .same(let a, let b):
                Text("Are **\(names[a] ?? "these")** and **\(names[b] ?? "these")** the same?")
                HStack {
                    Button("Same") { answer(question, .same) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("reviewSame-\(a)")
                    Button("Not the same") { answer(question, .notSame) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reviewNotSame-\(a)")
                    Spacer()
                    skip
                }
            case .whichOne(let unsure):
                if let entryDate {
                    Text("\u{201C}\(unsure.mention.surface)\u{201D} in your entry from \(entryDate.formatted(date: .abbreviated, time: .omitted)): which one?")
                } else {
                    Text("Which one did you mean by \u{201C}\(unsure.mention.surface)\u{201D}?")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(unsure.candidates) { candidate in
                            Button(candidate.name) { answer(question, .whichOne(candidate.id)) }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("whichOneCandidate-\(candidate.name)")
                        }
                        skip
                    }
                }
            }
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mindReviewCard")
    }

    private var skip: some View {
        Button("Skip") { answer(question, .skip) }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("reviewSkip")
    }
}
