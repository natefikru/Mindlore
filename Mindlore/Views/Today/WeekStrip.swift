import SwiftUI

// Seven days, present or not. No number, no target, nothing to keep up: a day you didn't write is
// an outline, not a gap. The tint is that day's first life area, so a glance reads as where the
// week went rather than how much of it you filled.
struct WeekStrip: View {
    let days: [WeekDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(day.hasEntry ? (day.tint?.color ?? Palette.ember) : .clear)
                        .overlay(Circle().strokeBorder(day.hasEntry ? .clear : Palette.hairline))
                        .frame(width: 9, height: 9)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("weekStrip")
    }

    private var label: String {
        let written = days.filter(\.hasEntry).count
        return written == 1 ? "1 day written this week" : "\(written) days written this week"
    }
}
