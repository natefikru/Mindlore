import SwiftUI

// What a thread card's buttons ask for. The header hands it up; EntryListView owns the store.
enum TodayThreadAction {
    case done, letGo, writeAbout
}

// The header above the journal: a greeting, the week, and one row of cards to swipe through each
// day. Everything here is a query over what the app already stored. Nothing asks the AI anything,
// and nothing keeps score.
struct TodayHeader: View {
    let today: Today
    let dismiss: (TodayCard) -> Void
    let mute: (EntityFacts) -> Void
    var act: (TodayThreadAction, LooseEndFacts) -> Void = { _, _ in }
    var openEntry: (UUID) -> Void = { _ in }
    var openReflect: () -> Void = {}
    @State private var position: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(today.greeting)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 16)
            WeekStrip(days: today.week, onTap: openReflect)
                .padding(.bottom, 2)
                .padding(.horizontal, 16)
            if !today.cards.isEmpty {
                row
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayHeader")
    }

    // One card per page. Every card takes the tallest one's height, so the row doesn't jump as it
    // pages; the horizontal swipe belongs to paging alone, which is why nothing here dismisses on
    // a swipe the way a lone card used to.
    private var row: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(today.cards) { card in
                        TodayCardView(
                            card: card,
                            dismiss: { advance(past: card); dismiss(card) },
                            mute: mute,
                            act: { action in
                                guard let end = card.thread else { return }
                                if action != .writeAbout { advance(past: card) }
                                act(action, end)
                            },
                            open: entryID(of: card).map { id in { openEntry(id) } }
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .containerRelativeFrame(.horizontal)
                        .id(card.id)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position)
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("todayRow")

            if today.cards.count > 1 {
                Text("\(currentIndex + 1) of \(today.cards.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("todayRowPosition")
            }
        }
    }

    private var currentIndex: Int {
        position.flatMap { id in today.cards.firstIndex { $0.id == id } } ?? 0
    }

    // A card leaving takes the reader to the one after it (or before, at the end), rather than
    // leaving the row pointed at an id that no longer exists.
    private func advance(past card: TodayCard) {
        guard let index = today.cards.firstIndex(of: card) else { return }
        let next = today.cards.indices.contains(index + 1) ? index + 1 : index - 1
        position = today.cards.indices.contains(next) ? today.cards[next].id : nil
    }

    private func entryID(of card: TodayCard) -> UUID? {
        switch card {
        case .onThisDay(let entry, _), .latestSummary(let entry): entry.id
        case .closed(let end), .dueToday(let end), .stillOpen(let end): end.sourceEntryID
        case .beenAWhile: nil
        }
    }
}

struct TodayCardView: View {
    let card: TodayCard
    let dismiss: () -> Void
    let mute: (EntityFacts) -> Void
    var act: (TodayThreadAction) -> Void = { _ in }
    var open: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(TodayCopy.title(card))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(card.kind == .dueToday ? Palette.ember : .secondary)
                Spacer(minLength: 8)
                // A thread stays until it's done, let go, or fades, so only a day card can be put
                // away until tomorrow.
                if card.thread == nil {
                    Button("Not today", systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .padding(-14)
                        .accessibilityIdentifier("todayDismiss-\(card.kind.rawValue)")
                }
            }
            // A button, not a tap gesture, so VoiceOver can open the entry too.
            if let open {
                Button(action: open) { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the entry")
            } else {
                content
            }
            Spacer(minLength: 0)
            if case .beenAWhile(let who) = card {
                Button("Don't show \(who.name)") { mute(who) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ember)
                    .padding(.top, 2)
                    .accessibilityIdentifier("todayMute")
            }
            if card.thread != nil {
                actions
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayCard-\(card.kind.rawValue)")
    }

    // The user's own words, in the user's own face, then when it was and, for a thread, when it
    // fades.
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            let body = TodayCopy.body(card)
            if !body.isEmpty {
                Text(body)
                    .journalText(.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .strikethrough(card.kind == .closed, color: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let detail = TodayCopy.detail(card) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let line = TodayCopy.threadLine(card, now: .now) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("todayFade")
            }
        }
    }

    // Three equal choices. Let it go used to be greyed out beside an ember Done, which read as the
    // app preferring one ending over the other, and nothing here should steer.
    private var actions: some View {
        HStack(spacing: 16) {
            action("Write about it", "square.and.pencil", .writeAbout)
                .accessibilityIdentifier("threadWrite")
            Spacer(minLength: 0)
            action("Let it go", "xmark", .letGo)
                .accessibilityIdentifier("threadLetGo")
            action("Done", "checkmark", .done)
                .accessibilityIdentifier("threadDone")
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ember)
        .padding(.top, 4)
    }

    // The icon hard against its word. A system Label here spaced them like a toolbar item.
    private func action(_ title: String, _ symbol: String, _ kind: TodayThreadAction) -> some View {
        Button { act(kind) } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(title)
            }
            // A 44pt target that takes no room: the padding widens what a tap can hit, and the
            // negative padding gives the space back, so the row sits on the card's bottom edge.
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .padding(.vertical, -12)
        }
        .accessibilityLabel(title)
    }
}
