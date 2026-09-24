import CoreGraphics
import Foundation

// Where each area's bubble sits in Life's field. Size is how much of the writing an area takes;
// height is how it feels against the author's usual, the dashed line through the middle. Bubbles
// then push each other sideways until none overlap, staying as close to their own height as they
// can. Pure and deterministic, so the same reading always draws the same picture and a window
// change moves bubbles rather than reshuffling them.
nonisolated enum LifeBubbleLayout {
    struct Bubble: Equatable, Sendable {
        let area: LifeArea
        let center: CGPoint
        let radius: CGFloat
    }

    static let minRadius: CGFloat = 22
    static let gap: CGFloat = 6
    // A height of this much (mean valence against the baseline) reaches the field's edge.
    static let fullHeight = 0.9

    // The share of the field the bubbles cover between them: room left to separate them.
    static let fill: CGFloat = 0.40

    static func layout(_ areas: [LifeSignals.AreaReading], in size: CGSize) -> [Bubble] {
        guard !areas.isEmpty, size.width > 0, size.height > 0 else { return [] }
        let mid = size.height / 2
        let maxRadius = min(size.width, size.height) * 0.24

        // Area follows share, then everything is scaled so the bubbles cover `fill` of the field.
        let raw = areas.map { CGFloat($0.share.squareRoot()) }
        let rawArea = raw.reduce(0) { $0 + .pi * $1 * $1 }
        let scale = rawArea > 0 ? (fill * size.width * size.height / rawArea).squareRoot() : 1
        let radii = raw.map { min(maxRadius, max(minRadius, $0 * scale)) }

        // Biggest first from the centre outwards, alternating sides, so the picture balances.
        let order = areas.indices.sorted { areas[$0].entries != areas[$1].entries ? areas[$0].entries > areas[$1].entries : areas[$0].area.rawValue < areas[$1].area.rawValue }
        var bubbles: [(area: LifeArea, x: CGFloat, y: CGFloat, targetY: CGFloat, r: CGFloat)] = []
        for (rank, index) in order.enumerated() {
            let reading = areas[index]
            let r = radii[index]
            let lift = CGFloat(max(-1, min(1, (reading.height ?? 0) / fullHeight)))
            let targetY = clamp(mid - lift * (mid - r - 4), r, size.height - r)
            let side: CGFloat = rank.isMultiple(of: 2) ? 1 : -1
            let step = CGFloat((rank + 1) / 2)
            let x = clamp(size.width / 2 + side * step * maxRadius * 0.8, r, size.width - r)
            bubbles.append((reading.area, x, targetY, targetY, r))
        }

        // Relax: pull each towards its own height, then separate every overlapping pair along the
        // line between them. Separation runs last, so what's drawn never overlaps unless the
        // field is simply too small.
        for iteration in 0..<400 {
            let pull: CGFloat = iteration < 300 ? 0.06 : 0
            for i in bubbles.indices {
                bubbles[i].y += (bubbles[i].targetY - bubbles[i].y) * pull
                bubbles[i].x += (size.width / 2 - bubbles[i].x) * pull * 0.05
            }
            for i in bubbles.indices {
                for j in bubbles.indices where j > i {
                    let dx = bubbles[j].x - bubbles[i].x
                    let dy = bubbles[j].y - bubbles[i].y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    let overlap = bubbles[i].r + bubbles[j].r + gap - distance
                    guard overlap > 0 else { continue }
                    // A deterministic direction when two share a centre.
                    let ux = distance < 0.01 ? (i.isMultiple(of: 2) ? 1 : -1) : dx / distance
                    let uy = distance < 0.01 ? 0 : dy / distance
                    // The smaller bubble moves more, so the big ones hold their heights.
                    let total = bubbles[i].r + bubbles[j].r
                    let shareI = bubbles[j].r / total
                    let shareJ = bubbles[i].r / total
                    bubbles[i].x -= ux * overlap * shareI
                    bubbles[i].y -= uy * overlap * shareI
                    bubbles[j].x += ux * overlap * shareJ
                    bubbles[j].y += uy * overlap * shareJ
                }
            }
            for i in bubbles.indices {
                bubbles[i].x = clamp(bubbles[i].x, bubbles[i].r, size.width - bubbles[i].r)
                bubbles[i].y = clamp(bubbles[i].y, bubbles[i].r, size.height - bubbles[i].r)
            }
        }
        return bubbles.map { Bubble(area: $0.area, center: CGPoint(x: $0.x, y: $0.y), radius: $0.r) }
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        high < low ? (low + high) / 2 : min(max(value, low), high)
    }
}
