import Foundation
import Testing
@testable import Mindlore

struct MindRegionsTests {
    @Test func everyVisibleAreaHasAFixedDistinctSpot() {
        let all = MindRegions.points(visible: LifeArea.allCases, entityCount: 100)
        #expect(all.count == LifeArea.allCases.count)
        #expect(Set(all.values.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded()))" }).count == all.count)
        #expect(all == MindRegions.points(visible: LifeArea.allCases.reversed(), entityCount: 100), "order of the input doesn't matter")

        let hidden = MindRegions.points(visible: LifeArea.allCases.filter { $0 != .play }, entityCount: 100)
        #expect(hidden[.play] == nil)
        #expect(hidden.count == LifeArea.allCases.count - 1)
    }

    @Test func theCircleGrowsWithTheJournal() {
        func radius(_ count: Int) -> Double {
            let point = MindRegions.points(visible: [.work, .home], entityCount: count)[.work]!
            return (point * point).sum().squareRoot()
        }
        #expect(radius(0) == 120)
        #expect(radius(400) > radius(100))
    }

    @Test func nodesTakeTheirAreasPoint() {
        let points = MindRegions.points(visible: [.work, .home], entityCount: 10)
        let person = GraphSimulation.Node(id: UUID(), kind: .person, linkCount: 1)
        let loner = GraphSimulation.Node(id: UUID(), kind: .person, linkCount: 1)
        let entry = GraphSimulation.Node(id: UUID(), kind: .other, linkCount: 1, isEntry: true)
        let result = MindRegions.nodePoints(
            nodes: [person, loner, entry],
            areaOf: [person.id: .home],
            entryAreas: [entry.id: [.play, .work]],
            points: points
        )
        #expect(result[person.id] == points[.home])
        #expect(result[loner.id] == nil)
        #expect(result[entry.id] == points[.work], "a hidden first area falls through to the next")
    }
}
