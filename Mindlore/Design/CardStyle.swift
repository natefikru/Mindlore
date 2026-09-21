import SwiftUI

// Continuous corners, three sizes: a card, a tile inside a card, and a chip (a capsule).
enum Corner {
    static let card: CGFloat = 24
    static let tile: CGFloat = 16
}

extension View {
    // An opaque content card: Card colour, a hairline, no shadow. Glass is for what floats over
    // content, never for content itself.
    func card(padding: CGFloat = 16, corner: CGFloat = Corner.card) -> some View {
        self
            .padding(padding)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Palette.hairline))
    }

    // Paper behind a List or Form. Without hiding the scroll content background the system's grouped
    // background wins and Paper never shows.
    func paperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
    }
}
