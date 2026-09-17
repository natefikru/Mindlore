import XCTest

// The graph canvas draws its nodes itself, so a test can't query where one is. It exposes
// "nodes=N focused=<name>" as its accessibility value instead, and these helpers tap outward
// from the centre until a tap lands on something.
extension XCUIElement {
    var graphFocus: String? {
        guard let value = value as? String, let range = value.range(of: "focused=") else { return nil }
        let name = String(value[range.upperBound...])
        return name == "none" ? nil : name
    }

    var graphNodeCount: Int? {
        guard let value = value as? String,
              let token = value.split(separator: " ").first(where: { $0.hasPrefix("nodes=") })
        else { return nil }
        return Int(token.dropFirst("nodes=".count))
    }

    // Taps a spiral of points around the centre and stops at the first one that focuses a node.
    // A tap that misses clears the focus, which is harmless, and nothing taps a focused node a
    // second time, so this never navigates away.
    @discardableResult
    func tapUntilGraphFocuses(step: CGFloat = 18, rings: Int = 6) -> String? {
        let center = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        var offsets: [CGVector] = [.zero]
        for ring in 1...rings {
            let radius = CGFloat(ring) * step
            let count = ring * 6
            for index in 0..<count {
                let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
                offsets.append(CGVector(dx: radius * cos(angle), dy: radius * sin(angle)))
            }
        }
        for offset in offsets {
            center.withOffset(offset).tap()
            if let focus = graphFocus { return focus }
        }
        return nil
    }
}
