import SwiftUI

// One card in the feed: a loose end still open, or the week's own generated summary. Tapping
// opens a new entry seeded with its prompt; the X dismisses it. No drag-to-dismiss: a custom
// DragGesture here fought the ScrollView's own vertical pan and made the whole feed unscrollable,
// since a plain `.gesture()` has no way to defer to an ancestor scroll view the way List's native
// `.swipeActions` does.
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
                        .foregroundStyle(.secondary)
                        // The glyph is 12 points; the target is the 44 a thumb needs, without
                        // pushing the title row apart.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .padding(-14)
                        .accessibilityIdentifier("reflectDismiss-\(item.id)")
                }
                // No line limit: a generated summary is deliberately short (two to four
                // sentences), so there's nothing here worth truncating with no way to see the rest.
                Text(item.body)
                    .journalText(.callout)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reflectQueueRow")
    }
}
