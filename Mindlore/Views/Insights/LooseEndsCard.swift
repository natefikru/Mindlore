import SwiftData
import SwiftUI

// The loose ends one entry left, and the ones it settled from earlier entries.
struct LooseEndsCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Query private var created: [LooseEnd]
    @Query private var settled: [LooseEnd]

    init(entryID: UUID) {
        let id: UUID? = entryID
        _created = Query(filter: #Predicate<LooseEnd> { $0.sourceEntryID == id }, sort: \.createdAt)
        _settled = Query(filter: #Predicate<LooseEnd> { $0.resolvedByEntryID == id && $0.sourceEntryID != id }, sort: \.createdAt)
    }

    var body: some View {
        if !created.isEmpty || !settled.isEmpty {
            InsightCard(title: "Loose ends", caption: "Open until a later entry settles them, or you do.", copyText: (created + settled).map(\.text).joined(separator: "\n")) {
                ForEach(created) { looseEnd in
                    row(looseEnd)
                }
                ForEach(settled) { looseEnd in
                    Label {
                        Text(looseEnd.text)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .accessibilityLabel("\(looseEnd.text), settled by this entry")
                    .accessibilityIdentifier("looseEndSettledHere")
                }
            }
        }
    }

    private func row(_ looseEnd: LooseEnd) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(looseEnd.text)
                        .strikethrough(looseEnd.status == .resolved)
                    if let caption = caption(looseEnd) {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: symbol(looseEnd.status))
                    .foregroundStyle(looseEnd.isOpen ? Color.accentColor : .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("looseEnd-\(looseEnd.status.rawValue)")
            Spacer()
            Menu {
                if looseEnd.isOpen {
                    Button("Mark done", systemImage: "checkmark") { set(looseEnd, .resolved) }
                    Button("Let it go", systemImage: "xmark") { set(looseEnd, .dismissed) }
                } else {
                    Button("Reopen", systemImage: "arrow.uturn.backward") { set(looseEnd, .open) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Change \(looseEnd.text)")
            }
            .accessibilityIdentifier("looseEndMenu")
        }
    }

    private func set(_ looseEnd: LooseEnd, _ status: LooseEndStatus) {
        saver.flush()
        looseEnd.setByUser(status)
        try? modelContext.save()
    }

    private func symbol(_ status: LooseEndStatus) -> String {
        switch status {
        case .open: "circle"
        case .resolved: "checkmark.circle"
        case .faded: "moon.zzz"
        case .dismissed: "xmark.circle"
        }
    }

    private func caption(_ looseEnd: LooseEnd) -> String? {
        switch looseEnd.status {
        case .open: looseEnd.dueDate.map { "By \($0.formatted(date: .abbreviated, time: .omitted))" }
        case .resolved: looseEnd.userTouched ? "Marked done" : "Settled by a later entry"
        case .faded: "Faded after going quiet"
        case .dismissed: "Let go"
        }
    }
}
