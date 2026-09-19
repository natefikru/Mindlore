import SwiftUI

// The header above the journal: a greeting, the week, and at most three cards. Everything here is
// a query over what the app already stored. Nothing asks the AI anything, and nothing keeps score.
struct TodayHeader: View {
    let today: Today
    let dismiss: (TodayCard) -> Void
    let mute: (EntityFacts) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(today.greeting)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Palette.ink)
            WeekStrip(days: today.week)
                .padding(.bottom, 2)
            ForEach(Array(today.cards.enumerated()), id: \.element.id) { index, card in
                TodayCardView(card: card, dismiss: { dismiss(card) }, mute: mute)
                    .transition(.bloom)
                    .animation(
                        Motion.resolve(Motion.settle, reduceMotion: reduceMotion)?
                            .delay(Double(index) * Motion.stagger),
                        value: today.cards
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayHeader")
    }
}

struct TodayCardView: View {
    let card: TodayCard
    let dismiss: () -> Void
    let mute: (EntityFacts) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(TodayCopy.title(card))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Not today", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("todayDismiss-\(card.kind.rawValue)")
            }
            // The user's own words, in the user's own face.
            let body = TodayCopy.body(card)
            if !body.isEmpty {
                Text(body)
                    .journalText(.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .strikethrough(card.kind == .closed, color: .secondary)
            }
            if let detail = TodayCopy.detail(card) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if case .beenAWhile(let who) = card {
                Button("Don't show \(who.name)") { mute(who) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ember)
                    .padding(.top, 2)
                    .accessibilityIdentifier("todayMute")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayCard-\(card.kind.rawValue)")
    }
}
