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
    // A finger within this of an option's centre is on it: a little more than the circle, since
    // the thumb covers what it points at.
    static let hitRadius: CGFloat = 44
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
    static func centers(around plus: CGPoint, options: [Option]) -> [Option: CGPoint] {
        var result: [Option: CGPoint] = [:]
        for (option, degrees) in zip(options, angles(count: options.count)) {
            let radians = degrees * .pi / 180
            result[option] = CGPoint(x: plus.x + radius * cos(radians), y: plus.y - lift - radius * sin(radians))
        }
        return result
    }

    static func option(at point: CGPoint, plus: CGPoint, options: [Option]) -> Option? {
        let centers = centers(around: plus, options: options)
        return options
            .map { ($0, distance(point, centers[$0] ?? plus)) }
            .filter { $0.1 <= hitRadius }
            .min { $0.1 < $1.1 }?
            .0
    }

    enum Release: Equatable {
        case choose(Option)
        case stayOpen
        case close
    }

    // What letting go means. A touch that opened the fan and never left the + leaves it open for a
    // tap. A touch that began with the fan already open is a close, unless it ends on an option.
    static func release(at point: CGPoint, plus: CGPoint, options: [Option], leftPlus: Bool, openedByThisTouch: Bool) -> Release {
        if let option = option(at: point, plus: plus, options: options) { return .choose(option) }
        guard openedByThisTouch else { return .close }
        return !leftPlus && distance(point, plus) <= plusHitRadius ? .stayOpen : .close
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
