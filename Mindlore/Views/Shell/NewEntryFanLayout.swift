import CoreGraphics
import Foundation

// Where the new-entry fan's options sit and what a touch on the + means. Pure geometry, no SwiftUI,
// so the tap-or-drag rules are tested without a view.
//
// The options rest on a half circle above the +, left to right: Write, Record, Photograph pages.
// Record takes the top, the easiest spot for the thumb that just touched the +. Without a camera
// the two left spread to the ends of the arc.
nonisolated enum NewEntryFanLayout {
    enum Option: String, CaseIterable, Identifiable, Sendable {
        case write, record, pages

        var id: String { rawValue }

        var title: String {
            switch self {
            case .write: "Write"
            case .record: "Record"
            case .pages: "Pages"
            }
        }

        var symbol: String {
            switch self {
            case .write: "square.and.pencil"
            case .record: "mic.fill"
            case .pages: "camera.fill"
            }
        }
    }

    static let radius: CGFloat = 112
    // The arc's centre sits this far above the +, so the side options and their labels clear the
    // tab bar's own labels.
    static let lift: CGFloat = 28
    static let optionDiameter: CGFloat = 64
    // The + itself, for "the finger never left it".
    static let plusHitRadius: CGFloat = 34

    static func options(pagesAvailable: Bool) -> [Option] {
        pagesAvailable ? [.write, .record, .pages] : [.write, .record]
    }

    // Degrees from the +'s right, counterclockwise: 150 is up and left, 90 straight up.
    static func angles(count: Int) -> [Double] {
        switch count {
        case 3: [150, 90, 30]
        case 2: [135, 45]
        default: Array(repeating: 90, count: count)
        }
    }

    // Each option's centre, in the same space as `plus` (y grows downward).
    // The recording strip sits between the bar and the arc while a recording runs, so the arc
    // rises by about its height then.
    static let accessoryLift: CGFloat = 58

    static func centers(around plus: CGPoint, options: [Option], extraLift: CGFloat = 0) -> [Option: CGPoint] {
        var result: [Option: CGPoint] = [:]
        for (option, degrees) in zip(options, angles(count: options.count)) {
            let radians = degrees * .pi / 180
            result[option] = CGPoint(x: plus.x + radius * cos(radians), y: plus.y - lift - extraLift - radius * sin(radians))
        }
        return result
    }

    // The half ring behind the options while a finger is down, and what a slide lands on: the ring
    // between these radii, cut into one wedge per option. Hovering by wedge rather than by circle is
    // what makes a radial menu forgiving: the whole slice counts, not just the button.
    static let ringInner: CGFloat = radius - 58
    static let ringOuter: CGFloat = radius + 56

    // Where the arc is centred: above the + by the lift, and by the strip while recording.
    static func arcCenter(_ plus: CGPoint, extraLift: CGFloat = 0) -> CGPoint {
        CGPoint(x: plus.x, y: plus.y - lift - extraLift)
    }

    // Each option's wedge, in degrees counterclockwise from the right: halfway to its neighbours,
    // and out to the ends of the half circle.
    static func sectors(options: [Option]) -> [Option: ClosedRange<Double>] {
        let angles = angles(count: options.count)
        var result: [Option: ClosedRange<Double>] = [:]
        for (index, option) in options.enumerated() {
            let upper = index == 0 ? 180 : (angles[index - 1] + angles[index]) / 2
            let lower = index == options.count - 1 ? 0 : (angles[index] + angles[index + 1]) / 2
            result[option] = lower...upper
        }
        return result
    }

    static func option(at point: CGPoint, plus: CGPoint, options: [Option], extraLift: CGFloat = 0) -> Option? {
        let center = arcCenter(plus, extraLift: extraLift)
        let reach = distance(point, center)
        guard reach >= ringInner, reach <= ringOuter else { return nil }
        // Counterclockwise from the right, with y growing downward on screen.
        let degrees = atan2(Double(center.y - point.y), Double(point.x - center.x)) * 180 / .pi
        guard degrees >= -8, degrees <= 188 else { return nil }
        let clamped = min(180, max(0, degrees))
        return sectors(options: options).first { $0.value.contains(clamped) }?.key
    }

    enum Release: Equatable {
        case choose(Option)
        case stayOpen
        case close
    }

    // What letting go means. A touch that opened the fan and never left the + leaves it open for a
    // tap. A touch that began with the fan already open is a close, unless it ends on an option.
    static func release(at point: CGPoint, plus: CGPoint, options: [Option], leftPlus: Bool, openedByThisTouch: Bool, extraLift: CGFloat = 0) -> Release {
        if let option = option(at: point, plus: plus, options: options, extraLift: extraLift) { return .choose(option) }
        guard openedByThisTouch else { return .close }
        return !leftPlus && distance(point, plus) <= plusHitRadius ? .stayOpen : .close
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
