import Foundation
import RealityKit
import SwiftUI

#if DEBUG

// Turns a settled GraphSimulation3D into RealityKit entities, once.
//
// The simulation works in the same points the 2D canvas does (radii 3.5 to 16, springs around
// 70), and RealityKit works in metres, so everything is built in simulation units and the root
// carries a single `metresPerUnit` scale. Keeping the conversion in one place means the layout
// numbers in the diagnostics line and in the tests are the same numbers as 2D's.
//
// Two meshes are shared by every node and every edge: a unit sphere and a unit cylinder, scaled
// per instance. Generating one mesh per node put the 300-node build in the seconds.
// RealityKit's Entity and the journal's own Entity are both in scope here; the graph's nodes are
// the journal's, and everything drawn is RealityKit's.
typealias SceneEntity = RealityKit.Entity

@MainActor
enum Graph3DScene {
    static let metresPerUnit: Float = 0.01
    // How many names the picture can carry before it stops being readable. Ordered by link count,
    // so the hubs keep theirs.
    static let labelBudget = 40
    static let edgeRadius: Float = 0.35
    static let labelHeight: Float = 3.2
    // A label's height as a fraction of what the camera can see at its resting distance. The size
    // was a fixed 7 units, which is a readable caption over 300 nodes and a billboard over four,
    // because a smaller graph is framed from closer in.
    static let labelScreenFraction: Float = 0.022

    struct Build {
        let root: SceneEntity
        // Node id by entity name, so a tap resolves without holding onto entities.
        let idByEntityName: [String: UUID]
    }

    // The visible height in simulation units at `metres` from the camera, which is what a label
    // has to be sized against for it to read the same at any node count.
    static func labelFontSize(atDistance metres: Float, fieldOfView: Float) -> CGFloat {
        let halfAngle = fieldOfView / 2 * .pi / 180
        let visible = 2 * (metres / metresPerUnit) * tan(halfAngle)
        return CGFloat(max(1, visible * labelScreenFraction))
    }

    static func build(_ layout: Graph3DLayout, names: [UUID: String], labelFontSize: CGFloat = 7) -> Build {
        let root = SceneEntity()
        root.scale = .init(repeating: metresPerUnit)

        let sphere = MeshResource.generateSphere(radius: 1)
        let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
        var materials: [EntityKind: RealityKit.Material] = [:]
        for kind in EntityKind.allCases {
            materials[kind] = SimpleMaterial(color: UIColor(kind.color), roughness: 0.4, isMetallic: false)
        }
        let edgeMaterial = UnlitMaterial(color: UIColor.gray.withAlphaComponent(0.35))

        var idByEntityName: [String: UUID] = [:]
        let nodes = layout.nodes

        for index in nodes.indices {
            let node = nodes[index]
            let model = ModelEntity(mesh: sphere, materials: [materials[node.kind] ?? materials[.other]!])
            let radius = Float(layout.radii[index])
            model.position = SIMD3<Float>(layout.positions[index])
            model.scale = .init(repeating: radius)
            // Named rather than referenced, so the tap handler looks up an id and the scene can
            // be thrown away without anything dangling.
            model.name = "node-\(node.id.uuidString)"
            idByEntityName[model.name] = node.id
            // The unit sphere's own collision shape, scaled by the entity, so the tap target is
            // exactly what is drawn.
            model.components.set(CollisionComponent(shapes: [.generateSphere(radius: 1)]))
            model.components.set(InputTargetComponent())
            root.addChild(model)
        }

        for pair in layout.edgeIndices {
            let a = SIMD3<Float>(layout.positions[pair.a])
            let b = SIMD3<Float>(layout.positions[pair.b])
            let delta = b - a
            let length = simd_length(delta)
            guard length > 0 else { continue }
            let model = ModelEntity(mesh: cylinder, materials: [edgeMaterial])
            model.position = (a + b) / 2
            // The unit cylinder runs along +Y; turn it to face the other end.
            model.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: delta / length)
            model.scale = SIMD3<Float>(edgeRadius, length, edgeRadius)
            root.addChild(model)
        }

        for node in labelled(nodes) {
            guard let name = names[node.id], !name.isEmpty,
                  let index = layout.index(of: node.id)
            else { continue }
            let label = textEntity(name, fontSize: labelFontSize)
            let above = Float(layout.radii[index]) + labelHeight
            label.position = SIMD3<Float>(layout.positions[index]) + SIMD3<Float>(0, above, 0)
            root.addChild(label)
        }

        return Build(root: root, idByEntityName: idByEntityName)
    }

    // The most-mentioned first, the same order the 2D label budget uses, and a stable tiebreak so
    // two runs label the same nodes.
    static func labelled(_ nodes: [GraphSimulation3D.Node]) -> [GraphSimulation3D.Node] {
        GraphSimulation.Node.layoutOrdered(nodes.filter { !$0.isEntry }).prefix(labelBudget).map { $0 }
    }

    // Text is built at simulation scale (the root shrinks it with everything else) and centred on
    // its own bounds, because generateText puts the origin at the baseline's left edge.
    private static func textEntity(_ string: String, fontSize: CGFloat) -> ModelEntity {
        let mesh = MeshResource.generateText(
            string,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: fontSize, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        let bounds = mesh.bounds
        entity.position = -bounds.center
        let holder = ModelEntity()
        holder.addChild(entity)
        // Always facing the camera, however the orbit has turned: a label edge-on is unreadable,
        // which is half of what the spike is meant to answer.
        holder.components.set(BillboardComponent())
        return holder
    }
}
#endif
