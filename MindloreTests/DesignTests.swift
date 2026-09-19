import SwiftUI
import Testing
import UIKit
@testable import Mindlore

// The palette lives in the asset catalog, where a missing or duplicated colour set fails silently: a
// misnamed colour draws as clear, and two areas sharing a hue look fine until they sit side by side.
@MainActor
struct DesignTests {
    private static let areaNames = ["AreaWork", "AreaMoney", "AreaHealth", "AreaMind", "AreaFamily", "AreaLove", "AreaFriends", "AreaPlay", "AreaHome"]
    private static let kindNames = ["KindPerson", "KindPlace", "KindOrganization", "KindProject", "KindEvent", "KindTag", "KindOther"]
    private static let surfaceNames = ["AccentColor", "Paper", "Card", "Ink"]

    private func resolved(_ name: String, _ style: UIUserInterfaceStyle) throws -> [CGFloat] {
        let color = try #require(UIColor(named: name), "no colour set named \(name)")
        let traits = UITraitCollection(userInterfaceStyle: style)
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { ($0 * 255).rounded() }
    }

    @Test func everyColourSetExistsInBothAppearances() throws {
        for name in Self.areaNames + Self.kindNames + Self.surfaceNames {
            let light = try resolved(name, .light)
            let dark = try resolved(name, .dark)
            #expect(light[3] == 255 && dark[3] == 255, "\(name) should be opaque")
            #expect(light != dark, "\(name) has no dark variant of its own")
        }
    }

    @Test func thereIsAColourSetForEveryAreaAndKind() {
        #expect(Self.areaNames.count == LifeArea.allCases.count)
        #expect(Self.kindNames.count == EntityKind.allCases.count)
    }

    @Test func noTwoAreasOrKindsShareAColour() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let areas = try Self.areaNames.map { try resolved($0, style) }
            let kinds = try Self.kindNames.map { try resolved($0, style) }
            #expect(Set(areas).count == areas.count)
            #expect(Set(kinds).count == kinds.count)
            // A kind is never mistaken for an area on the graph.
            #expect(Set(areas).isDisjoint(with: Set(kinds)))
        }
    }

    @Test func areaAndKindColoursAreDistinctAsSwiftUIColors() {
        #expect(Set(LifeArea.allCases.map { $0.color.description }).count == LifeArea.allCases.count)
        #expect(Set(EntityKind.allCases.map { $0.color.description }).count == EntityKind.allCases.count)
    }

    @Test func theJournalFontIsSerifAndFollowsTheBodySize() {
        let journal = UIFont.journal(.body)
        let body = UIFont.preferredFont(forTextStyle: .body)
        #expect(journal.pointSize == body.pointSize)
        #expect(journal.fontDescriptor.symbolicTraits.contains(.classModernSerifs) || journal.familyName != body.familyName)
        // The descriptor keeps its text style, which is what lets a text view rescale it.
        #expect(journal.fontDescriptor.object(forKey: .textStyle) as? String == UIFont.TextStyle.body.rawValue)
    }

    @Test func reduceMotionTurnsEveryMotionIntoACrossfadeAndStopsBreathing() {
        #expect(Motion.resolve(Motion.settle, reduceMotion: true) == Motion.reduced)
        #expect(Motion.resolve(Motion.bloom, reduceMotion: true) == Motion.reduced)
        #expect(Motion.resolve(Motion.carry, reduceMotion: true) == Motion.reduced)
        #expect(Motion.resolve(Motion.breathe, reduceMotion: true) == nil)
        #expect(Motion.resolve(Motion.bloom, reduceMotion: false) == Motion.bloom)
    }
}
