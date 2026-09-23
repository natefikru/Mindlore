import SwiftUI

// Journal, Note, or Creative, as three chips under an entry's title, so what an entry is can be
// settled with one tap rather than from a menu. The same row sits on the insights sheet, since
// that is where the consequences (no mood on a note, no names on a poem) are visible.
struct EntryKindPicker: View {
    let selection: EntryKind
    // Whether the choice was the user's. A model's guess is shown lighter, so a wrong one reads
    // as something to correct rather than something the user said.
    var setByUser = false
    var showsMeaning = false
    let onSelect: (EntryKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(EntryKind.allCases, id: \.self) { kind in
                    let selected = kind == selection
                    Button {
                        guard !selected else { return }
                        onSelect(kind)
                    } label: {
                        Label(kind.name, systemImage: kind.symbol)
                            .lineLimit(1)
                            .chip(tint: selected ? kind.color : nil, selected: selected)
                            .opacity(selected || setByUser ? 1 : 0.7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityHint(kind.meaning)
                    .accessibilityIdentifier("entryKind-\(kind.rawValue)")
                }
            }
            if showsMeaning {
                Text(selection.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entryKindPicker")
        .sensoryFeedback(Haptics.selected, trigger: selection)
    }
}

// The small capsule on a list row saying what the entry is.
struct EntryKindBadge: View {
    let kind: EntryKind

    var body: some View {
        Label(kind.name, systemImage: kind.symbol)
            .labelStyle(.titleOnly)
            .font(.caption)
            .foregroundStyle(kind.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(kind.color.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(kind.name) entry")
            .accessibilityIdentifier("kindBadge-\(kind.rawValue)")
    }
}
