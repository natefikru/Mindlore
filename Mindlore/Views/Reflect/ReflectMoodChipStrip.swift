import SwiftUI

// Small dots and words, the same visual language the Journal list row footer's area dots use, not
// a Charts bar graph. Sits in a week's header and on a collapsed month row. Grounded, glanceable,
// and it doesn't need its own screen to earn its place.
struct ReflectMoodChipStrip: View {
    let moodCounts: [MoodCategory: Int]
    var maxChips = 3

    private var moods: [MoodCategory] {
        moodCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .prefix(maxChips)
            .map(\.key)
    }

    var body: some View {
        if !moods.isEmpty {
            HStack(spacing: 10) {
                ForEach(moods, id: \.self) { mood in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(mood.color)
                            .frame(width: 6, height: 6)
                        Text(mood.name)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reflectMoodChips")
        }
    }
}
