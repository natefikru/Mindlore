import SwiftUI

// A row of small bars: how often a name came up across the window and the three stretches before
// it, oldest on the left. The window's own bars (the last quarter) are at full strength and the
// earlier ones muted, so "lately" reads at a glance. One Canvas, no Swift Charts.
struct Sparkline: View {
    let values: [Int]
    var color: Color = .secondary
    // How many of the trailing bars are "now". Mind's series covers four windows, so a quarter.
    var recentCount: Int?
    // Words for VoiceOver, since the bars alone say nothing to it.
    var accessibilityText: String?

    private var recent: Int { recentCount ?? max(1, values.count / 4) }

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let peak = Double(max(values.max() ?? 0, 1))
            let gap: Double = 1.5
            let width = (Double(size.width) - gap * Double(values.count - 1)) / Double(values.count)
            guard width > 0 else { return }
            var earlier = Path()
            var now = Path()
            for (index, value) in values.enumerated() {
                // An empty stretch still shows as a hairline, so a gap reads as quiet, not missing.
                let height = value == 0 ? 1 : max(2, Double(size.height) * Double(value) / peak)
                let rect = CGRect(
                    x: Double(index) * (width + gap),
                    y: Double(size.height) - height,
                    width: width,
                    height: height
                )
                if index >= values.count - recent {
                    now.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
                } else {
                    earlier.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
                }
            }
            context.fill(earlier, with: .color(color.opacity(0.35)))
            context.fill(now, with: .color(color))
        }
        .accessibilityElement()
        .accessibilityLabel("Mentions over time")
        .accessibilityValue(accessibilityText ?? "")
    }
}
