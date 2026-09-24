import SwiftData
import SwiftUI

// Reflect's Loose ends tab: every open loose end pinned at the top, then the closed ones newest first
// by the day of the entry that raised it, grouped by month (`ReflectLooseEnds.layout`). An open one can be
// marked done or let go, the two choices Today's thread card offers; a closed one can be reopened.
// A plain ScrollView over Paper, like the summaries beside it, not a List.
struct ReflectLooseEndsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(AppRouter.self) private var router
    @State private var items: [ReflectLooseEnds.Item] = []
    @State private var filter: ReflectLooseEnds.Filter = .all
    @State private var hasLoaded = false
    // Counts loose ends marked done here, so the tap back fires once per close.
    @State private var closed = 0

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No loose ends yet",
                    systemImage: "circle.dashed",
                    description: Text("When an entry leaves something open, like a call to make or an answer to wait for, it's kept here, and stays here once it's settled.")
                )
                .accessibilityIdentifier("reflectLooseEndsEmpty")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        filterChips
                        if layout.isEmpty {
                            Text(filter == .open ? "Nothing open right now." : "Nothing closed yet.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 24)
                                .accessibilityIdentifier("reflectLooseEndsFilteredEmpty")
                        }
                        if !layout.open.isEmpty {
                            openSection(layout.open)
                        }
                        ForEach(layout.months) { month in
                            monthSection(month)
                        }
                    }
                    .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: items)
                    .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: filter)
                }
                .accessibilityIdentifier("reflectLooseEnds")
            }
        }
        .paperBackground()
        .task(id: fingerprint) { load() }
        .sensoryFeedback(Haptics.looseEndClosed, trigger: closed)
    }

    private var layout: ReflectLooseEnds.Layout {
        ReflectLooseEnds.layout(items, filter: filter)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(ReflectLooseEnds.Filter.allCases) { option in
                let selected = filter == option
                Button {
                    filter = option
                } label: {
                    Text("\(option.title) \(ReflectLooseEnds.filtered(items, by: option).count)")
                        .chip(tint: Palette.ember, selected: selected)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("reflectLooseEndsFilter-\(option.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .sensoryFeedback(Haptics.selected, trigger: filter)
    }

    private func openSection(_ open: [ReflectLooseEnds.Item]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Open")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ember)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("reflectLooseEndsOpenHeader")
            ForEach(open) { item in
                row(item)
            }
            Divider().padding(.leading, 16)
        }
    }

    private func monthSection(_ month: ReflectLooseEnds.Month) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ReflectLooseEnds.monthTitle(month.start))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(month.items) { item in
                row(item)
            }
            Divider().padding(.leading, 16)
        }
    }

    private func row(_ item: ReflectLooseEnds.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // The shape carries the status; the colour only repeats it.
            Image(systemName: ReflectLooseEnds.symbol(item.status))
                .foregroundStyle(item.isOpen ? Palette.ember : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .strikethrough(item.status == .resolved)
                    .journalText(.body)
                    .foregroundStyle(item.isOpen ? Palette.ink : Color.secondary)
                    .multilineTextAlignment(.leading)
                Text("\(ReflectLooseEnds.statusTitle(item.status)) \u{00B7} \(ReflectLooseEnds.detail(item))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.subjects.isEmpty {
                    Label(item.subjects.joined(separator: ", "), systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reflectLooseEnd-\(item.status.rawValue)")
            Menu {
                actions(item)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Change \(item.text)")
            }
            .padding(-10)
            .accessibilityIdentifier("reflectLooseEndMenu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func actions(_ item: ReflectLooseEnds.Item) -> some View {
        if item.isOpen {
            Button("Mark done", systemImage: "checkmark") { apply(.done, to: item) }
            Button("Let it go", systemImage: "xmark") { apply(.letGo, to: item) }
        } else {
            Button("Reopen", systemImage: "arrow.uturn.backward") { apply(.reopen, to: item) }
        }
        if let entryID = item.sourceEntryID {
            Button("Open entry", systemImage: "doc.text") { openEntry(entryID) }
        }
    }

    // Today's fingerprint: the three monotonic counters, never a count.
    private struct Fingerprint: Equatable {
        let saver: Int
        let graph: Int
        let stamped: Int
    }

    private var fingerprint: Fingerprint {
        Fingerprint(saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision)
    }

    private func load() {
        items = ReflectLooseEndSource.items(in: modelContext)
        hasLoaded = true
    }

    // Reloaded here, not left to the fingerprint: JournalSaves.revision is a plain static SwiftUI
    // doesn't observe. Today picks the change up when this sheet closes, since closing it redraws
    // the journal list and its fingerprint reads the new revision.
    private func apply(_ action: ReflectLooseEndSource.Action, to item: ReflectLooseEnds.Item) {
        saver.flush()
        guard ReflectLooseEndSource.apply(action, to: item.id, in: modelContext) else {
            load()
            return
        }
        if action == .done { closed += 1 }
        load()
    }

    // Leaves Reflect for the entry, in read mode, the way a search result opens one. The router's
    // jump closes this sheet.
    private func openEntry(_ id: UUID) {
        guard ReflectLooseEndSource.entryExists(id, in: modelContext) else { return }
        router.showEntry(id, forReading: true)
    }
}
