import Foundation

#if DEBUG

// What graph.rendered3D logs, once per appearance of the spike. Deliberately the same shape as
// GraphRenderStats so the 2D and 3D lines in diagnostics.jsonl can be read side by side: the
// spike feeds the same FrameTimeSampler, so the percentiles mean the same thing.
//
// Counts and durations only. No id belongs here either: the spike names nothing it draws.
nonisolated struct Graph3DRenderStats: Equatable, Sendable {
    let nodes: Int
    let edges: Int
    // Nil when the layout ran out of its tick budget before settling.
    let settleMilliseconds: Double?
    let frameSamples: Int
    let frameP50Milliseconds: Double?
    let frameP95Milliseconds: Double?
}

extension GraphServices {
    // Lives with the spike so deleting the folder deletes the event.
    func recordGraph3DRendered(_ stats: Graph3DRenderStats) {
        var fields: [String: DiagnosticValue] = [
            "nodes": .int(stats.nodes),
            "edges": .int(stats.edges),
            "frameSamples": .int(stats.frameSamples),
        ]
        let optional: [(String, Double?)] = [
            ("settleMilliseconds", stats.settleMilliseconds),
            ("frameP50Milliseconds", stats.frameP50Milliseconds),
            ("frameP95Milliseconds", stats.frameP95Milliseconds),
        ]
        for (key, value) in optional {
            if let value { fields[key] = .double(value) }
        }
        diagnostics.record("graph.rendered3D", fields)
    }
}
#endif
