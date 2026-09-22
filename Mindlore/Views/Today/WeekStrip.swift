import SwiftUI

// Seven days, present or not. No number, no target, nothing to keep up: a day you didn't write is
// an outline, not a gap. The tint is that day's first life area, so a glance reads as where the
// week went rather than how much of it you filled. Reflect's way in (tasks/phase-b-ux.md): a tap
// opens the week/month look-back.
//
// The dots alone hid that: no chevron, no label, nothing sighted that said "this opens something."
// A plain "Reflect ›" caption sits at the trailing edge of the same row, same tap target. Not
// "Reflect on this week": the sheet that opens carries its own period control and isn't scoped to
// whichever week you tapped, so wording that implied otherwise would be wrong the first time
// someone stepped it back to a month.
struct WeekStrip: View {
    let days: [WeekDay]
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 4) {
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
                HStack(spacing: 2) {
                    Text("Reflect")
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Palette.ember)
                .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Opens Reflect")
        .accessibilityIdentifier("weekStrip")
    }

    private var label: String {
        let written = days.filter(\.hasEntry).count
        let week = written == 1 ? "1 day written this week" : "\(written) days written this week"
        return "\(week). Reflect."
    }
}
