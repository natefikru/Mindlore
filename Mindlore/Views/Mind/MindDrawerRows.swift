import SwiftUI

// "What changed": up to four small cards across the top of the drawer, each a name, the change,
// and the numbers as words. A tap focuses the name on the map, as a row tap does.
struct MindChangesRow: View {
    let cards: [MindDrawer.ChangeCard]
    let tap: (MindDrawer.ChangeCard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What changed")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(cards) { card in
                        Button { tap(card) } label: { cardView(card) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mindChange-\(card.name)")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        // Cards of a fixed width: past this the words overflowed them.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func cardView(_ card: MindDrawer.ChangeCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: card.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(card.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Text(MindDrawer.title(card.change.kind))
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.ember)
            Text(card.words)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
        }
        .frame(width: 170, alignment: .leading)
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// One name in the window: its area, its kind, a sparkline, how many entries named it, the change
// word when it is in the changes, and its open threads.
struct MindRankedRow: View {
    let row: MindDrawer.RankedRow
    let areaName: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(row.area?.color ?? Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(areaName ?? "No area")
                Image(systemName: row.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let change = row.change {
                        Text(MindDrawer.title(change))
                            .font(.caption)
                            .foregroundStyle(Palette.ember)
                    }
                }
                Spacer(minLength: 8)
                if row.openLooseEnds > 0 {
                    Text("\(row.openLooseEnds) open")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.fill.tertiary, in: Capsule())
                        .accessibilityIdentifier("mindRowOpen-\(row.name)")
                }
                Sparkline(values: row.series, color: row.area?.color ?? .secondary, accessibilityText: countWords)
                    .frame(width: 56, height: 18)
                Text("\(row.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
                    .accessibilityLabel(countWords)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var countWords: String {
        row.count == 1 ? "1 entry in this stretch" : "\(row.count) entries in this stretch"
    }
}
