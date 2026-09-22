import SwiftUI

// One card in the feed: a loose end, a quiet name, or something the AI noticed. Tapping opens a
// new entry seeded with its prompt; swiping or the X dismisses it, the same as Today's cards.
struct ReflectQueueRow: View {
    let item: ReflectQueueItem
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Not today", systemImage: "xmark", action: onDismiss)
                        .labelStyle(.iconOnly)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("reflectDismiss-\(item.id)")
                }
                Text(item.body)
                    .journalText(.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Not today", role: .destructive, action: onDismiss)
        }
        .accessibilityIdentifier("reflectQueueRow")
    }
}
