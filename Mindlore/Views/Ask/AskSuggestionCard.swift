import SwiftUI

// One suggested question on the empty Ask screen. The glyph says what kind of question it is, so
// three suggestions read as three different ways in rather than one template three times.
struct AskSuggestionCard: View {
    let suggestion: AskSuggestion
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ember)
                    .frame(width: 34, height: 34)
                    .background(Palette.ember.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text(verbatim: suggestion.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .card(padding: 14, corner: Corner.tile)
            .contentShape(RoundedRectangle(cornerRadius: Corner.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Puts this question in the field")
        .accessibilityIdentifier("askExample")
    }

    private var symbol: String {
        switch suggestion.source {
        case .name(let kind): kind.symbol
        case .thread: "circle.dashed"
        case .area(let area): area.symbol
        case .time: "calendar"
        }
    }
}
