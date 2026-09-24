import SwiftData
import SwiftUI

// "About you": the month's portrait, five short parts that each cite the entries they rest on.
// Written once a month, on the first visit to Life that month when AI answers through OpenAI, and
// kept, so earlier ones can be read again. Each line can be marked right or not quite (with a
// note), which the next portrait is told; it can be talked through in Chat or written about.
struct LifePortraitCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(AppRouter.self) private var router

    let reading: LifeSignals.Reading
    var onWritten: () -> Void = {}

    @State private var portrait: LifeWords.PortraitView?
    @State private var status: Status = .idle
    @State private var earlier: [LifeWords.PortraitView] = []
    @State private var showingEarlier = false
    @State private var sources: SourceList?
    @State private var noteFor: String?
    @State private var note = ""
    @State private var verdicts: [String: Bool] = [:]
    // One automatic try per appearance, so a failure doesn't ask again on every redraw.
    @State private var triedAutomatically = false
    @State private var showingAISettings = false

    enum Status: Equatable {
        case idle, writing, needsCloud, unavailable, failed
    }

    struct SourceList: Identifiable {
        let id = UUID()
        let entryIDs: [UUID]
    }

    var body: some View {
        LifeCard(title: "About you", symbol: "person.crop.circle", tint: Palette.ember) {
            VStack(alignment: .leading, spacing: 16) {
                if let portrait, portrait.concern {
                    LifeConcernView()
                } else if let portrait {
                    lines(portrait)
                    footer(portrait)
                } else {
                    placeholder
                }
            }
            .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: portrait)
        }
        .accessibilityIdentifier("lifePortrait")
        .task { await load() }
        .sheet(item: $sources) { list in
            NavigationStack {
                LifeSourcesView(entryIDs: list.entryIDs) { id in
                    sources = nil
                    router.showEntry(id, forReading: true, returningTo: .reflect)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingAISettings, onDismiss: { Task { await write() } }) {
            AISettingsSheet()
        }
        .sheet(isPresented: $showingEarlier) {
            NavigationStack {
                LifeEarlierPortraits(portraits: earlier)
            }
        }
        .alert("Not quite?", isPresented: Binding(get: { noteFor != nil }, set: { if !$0 { noteFor = nil } })) {
            TextField("What's closer to true (optional)", text: $note)
            Button("Save") { saveNotQuite() }
            Button("Cancel", role: .cancel) { noteFor = nil }
        } message: {
            Text("The next portrait is told, and won't say it again.")
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch status {
        case .writing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading your year…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("lifePortraitWriting")
        case .needsCloud, .unavailable:
            // One row and a way forward, not an apology where a portrait should be.
            HStack(alignment: .center, spacing: 12) {
                Text("A short portrait each month, written with OpenAI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Set up") { showingAISettings = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("lifePortraitSetUp")
            }
        case .failed, .idle:
            VStack(alignment: .leading, spacing: 10) {
                Text("A short portrait of what your year says about you, with the entries behind every line.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Write my portrait") { Task { await write() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("lifePortraitWrite")
            }
        }
    }

    private func lines(_ portrait: LifeWords.PortraitView) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(LifePrompts.Section.allCases, id: \.self) { section in
                let those = portrait.lines.filter { $0.section == section }
                if !those.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(section.title, systemImage: section.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ForEach(Array(those.enumerated()), id: \.offset) { _, line in
                            lineRow(line)
                        }
                    }
                }
            }
        }
    }

    private func lineRow(_ line: LifePrompts.Line) -> some View {
        let verdict = verdicts[line.text]
        return VStack(alignment: .leading, spacing: 8) {
            Text(line.text)
                .font(.body)
                .foregroundStyle(verdict == false ? Color.secondary : Palette.ink)
                .strikethrough(verdict == false, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                if !line.entryIDs.isEmpty {
                    Button {
                        sources = SourceList(entryIDs: line.entryIDs)
                    } label: {
                        Label("\(line.entryIDs.count) \(line.entryIDs.count == 1 ? "entry" : "entries")", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("lifePortraitSources")
                }
                Spacer()
                Button {
                    LifeWords.give(true, on: line.text, in: modelContext)
                    verdicts[line.text] = true
                } label: {
                    Image(systemName: verdict == true ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityLabel("That's right")
                .accessibilityIdentifier("lifePortraitRight")
                Button {
                    note = ""
                    noteFor = line.text
                } label: {
                    Image(systemName: verdict == false ? "xmark.circle.fill" : "xmark.circle")
                }
                .accessibilityLabel("Not quite")
                .accessibilityIdentifier("lifePortraitNotQuite")
                Menu {
                    Button("Talk about it", systemImage: "bubble.left.and.bubble.right") {
                        router.showAsk(question: "You noticed: \"\(line.text)\" Can we talk about that?")
                    }
                    Button("Write about it", systemImage: "square.and.pencil") {
                        router.showNewEntry(startingText: line.text, returningTo: .reflect)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .sensoryFeedback(Haptics.selected, trigger: verdict)
        }
    }

    private func footer(_ portrait: LifeWords.PortraitView) -> some View {
        HStack {
            Text(portrait.month.formatted(.dateTime.month(.wide).year()))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if earlier.count > 1 {
                Button("Earlier portraits") { showingEarlier = true }
                    .font(.caption.weight(.medium))
                    .accessibilityIdentifier("lifeEarlierPortraits")
            }
        }
    }

    private func load() async {
        earlier = LifeWords.portraits(in: modelContext)
        portrait = LifeWords.portraitForThisMonth(in: modelContext) ?? nil
        refreshVerdicts()
        if portrait == nil, !triedAutomatically {
            triedAutomatically = true
            await write()
        }
    }

    private func write() async {
        status = .writing
        let priorities = LifeSignals.priorities(settings.priorityAreas, reading: reading, visibleCount: settings.visibleLifeAreas.count)
        let outcome = await LifeWords.writePortrait(
            reading: reading,
            priorities: priorities,
            name: settings.name(of:),
            resolve: { AIServices.askGenerator(settings: settings, accounts: accounts) },
            in: modelContext
        )
        switch outcome {
        case .written(let written):
            portrait = written
            onWritten()
            earlier = LifeWords.portraits(in: modelContext)
            status = .idle
        case .needsCloud: status = .needsCloud
        case .unavailable: status = .unavailable
        case .failed: status = .failed
        }
        refreshVerdicts()
    }

    private func refreshVerdicts() {
        guard let portrait else { return }
        var result: [String: Bool] = [:]
        for line in portrait.lines {
            if let verdict = LifeWords.verdict(on: line.text, in: modelContext) { result[line.text] = verdict }
        }
        verdicts = result
    }

    private func saveNotQuite() {
        guard let line = noteFor else { return }
        LifeWords.give(false, on: line, note: note, in: modelContext)
        verdicts[line] = false
        noteFor = nil
    }
}

// Shown instead of the portrait when what was written sounds like someone may be in danger. Life
// stops reading the journal back and points somewhere a person can help.
struct LifeConcernView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Some of what you wrote lately sounds really heavy. You don't have to carry it on your own.")
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("If you're thinking about hurting yourself or you're in danger, please reach out now. In the US you can call or text 988, any time. Elsewhere, your local emergency number or a helpline can help.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                // 988 is the US line; everywhere else gets the directory of local ones.
                if Locale.current.region == .unitedStates, let call = URL(string: "tel:988") {
                    Link(destination: call) { Label("Call 988", systemImage: "phone.fill") }
                        .buttonStyle(.borderedProminent)
                }
                if let find = URL(string: "https://findahelpline.com") {
                    Link(destination: find) { Label("Find a helpline", systemImage: "globe") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .accessibilityIdentifier("lifeConcern")
    }
}

// The entries a portrait line rests on.
struct LifeSourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let entryIDs: [UUID]
    let open: (UUID) -> Void
    @State private var rows: [LifeSource.EntryRow] = []

    var body: some View {
        List(rows) { row in
            Button { open(row.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.title.isEmpty ? "Untitled" : row.title)
                            .journalText(.headline)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(row.date, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !row.preview.isEmpty {
                        Text(row.preview)
                            .journalText(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .paperBackground()
        .navigationTitle("Where this comes from")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { rows = LifeSource.entryRows(entryIDs, limit: 20, context: modelContext) }
    }
}

struct LifeEarlierPortraits: View {
    @Environment(\.dismiss) private var dismiss
    let portraits: [LifeWords.PortraitView]

    var body: some View {
        List {
            ForEach(portraits) { portrait in
                Section(portrait.month.formatted(.dateTime.month(.wide).year())) {
                    if portrait.concern {
                        Text("Set aside that month.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(portrait.lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(line.text)
                        }
                    }
                }
            }
        }
        .paperBackground()
        .navigationTitle("Earlier portraits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}
