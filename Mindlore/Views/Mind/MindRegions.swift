import Foundation

// Where each life area gathers when the map groups by area: every visible area has a fixed spot
// on a circle, in LifeArea's order, whether or not anything is filed under it yet. The radius
// follows the journal's size (the snapshot's entity count), which a replay step or the entries
// toggle never changes, so the spots hold still.
nonisolated enum MindRegions {
    static func points(visible: [LifeArea], entityCount: Int) -> [LifeArea: SIMD2<Double>] {
        let ordered = LifeArea.allCases.filter(visible.contains)
        guard !ordered.isEmpty else { return [:] }
        let radius = max(120, 22 * Double(max(entityCount, 0)).squareRoot())
        var points: [LifeArea: SIMD2<Double>] = [:]
        for (index, area) in ordered.enumerated() {
            // Starting at the top and going clockwise.
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(ordered.count)
            points[area] = SIMD2(radius * cos(angle), radius * sin(angle))
        }
        return points
    }

    // Each node's point: an entity takes its primary area's, an entry dot its first area's.
    static func nodePoints(
        nodes: [GraphSimulation.Node],
        areaOf: [UUID: LifeArea],
        entryAreas: [UUID: [LifeArea]],
        points: [LifeArea: SIMD2<Double>]
    ) -> [UUID: SIMD2<Double>] {
        var result: [UUID: SIMD2<Double>] = [:]
        for node in nodes {
            let area = node.isEntry ? entryAreas[node.id]?.first(where: { points[$0] != nil }) : areaOf[node.id]
            if let area, let point = points[area] { result[node.id] = point }
        }
        return result
    }
}
