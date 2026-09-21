import Foundation
import Testing
@testable import Mindlore

// The spike's camera. The settled cloud does not sit on the origin, so what the camera looks at
// and what it measures its distance from both have to be the cloud's own centre.
@MainActor
struct Spike3DFramingTests {
    private func layout(offsetBy offset: SIMD3<Double>) -> Graph3DLayout {
        let made = (0..<8).map { _ in GraphSimulation3D.Node(id: UUID(), kind: .person, linkCount: 1) }
        let positions = (0..<8).map { index -> SIMD3<Double> in
            let angle = Double(index) / 8 * 2 * .pi
            return SIMD3(cos(angle) * 10, sin(angle) * 10, 0) + offset
        }
        return Graph3DLayout(
            nodes: made,
            edgeIndices: [],
            positions: positions,
            radii: made.map { _ in 4 },
            settleMilliseconds: 1,
            indexByID: Dictionary(uniqueKeysWithValues: made.enumerated().map { ($1.id, $0) })
        )
    }

    @Test func theCentreIsTheCloudsOwnMiddleNotTheOrigin() {
        let centre = Mind3DSpikeModel.centre(layout(offsetBy: SIMD3(50, 0, 0)))

        #expect(abs(centre.x - 50) < 0.001)
        #expect(abs(centre.y) < 0.001)
    }

    // Measured from the origin, a cloud sitting 50 units away reads as far wider than it is, so the
    // camera pulls back and puts the picture off to one side. This is what left a four-node graph
    // looking like an empty page.
    @Test func framingMeasuresTheCloudNotItsDistanceFromTheOrigin() {
        let offset = layout(offsetBy: SIMD3(50, 0, 0))
        let centred = layout(offsetBy: .zero)

        let aboutCentre = Mind3DSpikeModel.framingDistance(offset, about: Mind3DSpikeModel.centre(offset))
        let aboutOrigin = Mind3DSpikeModel.framingDistance(offset)

        #expect(aboutOrigin > aboutCentre * 2, "measuring from the origin inflates the radius")
        #expect(abs(aboutCentre - Mind3DSpikeModel.framingDistance(centred)) < 0.001,
                "where the cloud sits makes no difference once it is measured about itself")
    }

    // A label was a fixed 7 units, which is a caption over 300 nodes and a billboard over four,
    // because a smaller graph is framed from closer in.
    @Test func labelsKeepTheirSizeOnScreenAtAnyNodeCount() {
        let near = Graph3DScene.labelFontSize(atDistance: 0.5, fieldOfView: 60)
        let far = Graph3DScene.labelFontSize(atDistance: 2.0, fieldOfView: 60)

        #expect(far > near)
        #expect(abs(far / near - 4) < 0.01, "four times the distance, four times the size")
        #expect(near >= 1)
    }
}
