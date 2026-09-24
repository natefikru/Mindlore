import SwiftUI

// A capsule chip: a tinted wash with matching text when it carries a colour (an area), neutral ink on
// a quiet fill when it doesn't (a mood, which is never coloured good or bad).
struct ChipStyle: ViewModifier {
    var tint: Color?
    var selected = false

    func body(content: Content) -> some View {
        content
            // A chip's icon sits close to its word; the system label's gap made each chip read as
            // two things (owner, 2026-09-24).
            .labelStyle(ChipLabelStyle())
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(tint ?? .primary))
            .background(fill, in: Capsule())
    }

    private var fill: AnyShapeStyle {
        guard let tint else { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(tint.opacity(selected ? 1 : 0.16))
    }
}

extension View {
    func chip(tint: Color? = nil, selected: Bool = false) -> some View {
        modifier(ChipStyle(tint: tint, selected: selected))
    }
}

struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}
