import SwiftUI

// How Mind colours its map. A lens changes paint only, never which nodes are on the map.
nonisolated enum MindLens: String, CaseIterable, Sendable {
    case kind, mood, recency

    var title: String {
        switch self {
        case .kind: "Kinds"
        case .mood: "Mood around"
        case .recency: "Recent"
        }
    }

    var symbol: String {
        switch self {
        case .kind: "circle.grid.2x2"
        case .mood: "face.smiling"
        case .recency: "sparkles"
        }
    }

    // The paint for the nodes on the map, or nil for plain kind colours. `onMap` is the entity
    // ids the simulation holds (entry dots are always grey and never need a slot).
    @MainActor
    func paint(_ snapshot: MindMapSnapshot, onMap: Set<UUID>, asOf: Date, generation: Int) -> GraphPaint? {
        switch self {
        case .kind:
            return nil
        case .mood:
            let moods = MindMap.moodAround(snapshot, asOf: asOf)
            var slots: [UUID: Int] = [:]
            for id in onMap {
                if let mood = moods[id], let slot = MoodCategory.allCases.firstIndex(of: mood) {
                    slots[id] = slot
                }
            }
            return GraphPaint(
                generation: generation,
                palette: MoodCategory.allCases.map(\.color),
                slotByID: slots,
                neutralUnslotted: true
            )
        case .recency:
            let recent = Set(MindMap.recentMentions(snapshot, asOf: asOf).keys).intersection(onMap)
            return GraphPaint(generation: generation, faded: onMap.subtracting(recent), glowing: recent)
        }
    }

    // The mood categories the paint uses, in their own order, for the legend.
    @MainActor
    static func moodsShown(in paint: GraphPaint?) -> [MoodCategory] {
        guard let paint else { return [] }
        let used = Set(paint.slotByID.values)
        return MoodCategory.allCases.enumerated().filter { used.contains($0.offset) }.map(\.element)
    }
}

// Names what the colours mean while a lens other than Kinds is on.
struct MindLensLegend: View {
    let lens: MindLens
    let paint: GraphPaint?

    var body: some View {
        Group {
            switch lens {
            case .kind:
                EmptyView()
            case .mood:
                let moods = MindLens.moodsShown(in: paint)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if moods.isEmpty {
                            Text("No moods yet")
                        }
                        ForEach(moods, id: \.self) { mood in
                            HStack(spacing: 4) {
                                Circle().fill(mood.color).frame(width: 8, height: 8)
                                Text(mood.name)
                            }
                        }
                        HStack(spacing: 4) {
                            Circle().fill(.gray.opacity(0.6)).frame(width: 8, height: 8)
                            Text("No mood")
                        }
                    }
                    .padding(.horizontal, 12)
                }
            case .recency:
                Text("Glowing: mentioned in the last \(MindMap.recentDays) days")
                    .padding(.horizontal, 12)
            }
        }
        .font(.caption)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mindLensLegend")
    }
}
