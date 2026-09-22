import SwiftUI

// The header above the journal: a greeting, the week, and at most three cards. Everything here is
// a query over what the app already stored. Nothing asks the AI anything, and nothing keeps score.
struct TodayHeader: View {
    let today: Today
    let dismiss: (TodayCard) -> Void
    let mute: (EntityFacts) -> Void
    var openReflect: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(today.greeting)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Palette.ink)
            WeekStrip(days: today.week, onTap: openReflect)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Plain @State, not @GestureState: a @GestureState resets to zero the instant the gesture
    // ends, which is exactly the moment a past-threshold swipe needs to keep going, off-screen,
    // rather than snapping back.
    @State private var dragOffset: CGFloat = 0
    @State private var leaving = false

    private static let dismissThreshold: CGFloat = 90

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
        .offset(x: dragOffset)
        .opacity(leaving ? 0 : 1)
        // The X button stays the accessible, discoverable way to dismiss; this is the faster
        // gesture for a sighted hand already touching the card. `minimumDistance` keeps a vertical
        // scroll of the list from being read as a swipe.
        .gesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    guard abs(value.translation.width) > Self.dismissThreshold else {
                        withAnimation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion)) { dragOffset = 0 }
                        return
                    }
                    let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                    withAnimation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion)) {
                        dragOffset = direction * 600
                        leaving = true
                    }
                    // Bloom transition already animates a card's removal from `today.cards`; this
                    // just lets the fly-out finish before the array changes under it, or the two
                    // animations fight over the same frame.
                    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.2)) { dismiss() }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayCard-\(card.kind.rawValue)")
    }
}
