import Foundation
import Testing
@testable import Mindlore

struct ReflectDismissalTests {
    @Test func aPeriodKeyCombinesKindAndStart() {
        let start = Date(timeIntervalSince1970: 1_757_289_600)
        #expect(ReflectDismissal.periodKey(kind: .week, periodStart: start) == "week:1757289600")
        #expect(ReflectDismissal.periodKey(kind: .month, periodStart: start) == "month:1757289600")
    }

    @Test func aDismissedItemStaysDismissedForItsPeriod() {
        var dismissal = ReflectDismissal()
        dismissal.dismiss("looseEnd:abc", for: "week:100")

        #expect(dismissal.itemIDs(for: "week:100") == ["looseEnd:abc"])
    }

    // Unlike Today, a period never expires: it's keyed by the period itself, not by day, so
    // there's no "tomorrow" for it to reset on.
    @Test func aDismissalNeverExpires() {
        var dismissal = ReflectDismissal()
        dismissal.dismiss("looseEnd:abc", for: "week:100")

        #expect(dismissal.itemIDs(for: "week:100") == ["looseEnd:abc"], "still dismissed, whatever day this is read on")
    }

    @Test func differentPeriodsKeepSeparateDismissals() {
        var dismissal = ReflectDismissal()
        dismissal.dismiss("looseEnd:abc", for: "week:100")
        dismissal.dismiss("quietName:def", for: "month:200")

        #expect(dismissal.itemIDs(for: "week:100") == ["looseEnd:abc"])
        #expect(dismissal.itemIDs(for: "month:200") == ["quietName:def"])
    }

    @Test func severalItemsCanBeDismissedInOnePeriod() {
        var dismissal = ReflectDismissal()
        dismissal.dismiss("looseEnd:abc", for: "week:100")
        dismissal.dismiss("quietName:def", for: "week:100")

        #expect(dismissal.itemIDs(for: "week:100") == ["looseEnd:abc", "quietName:def"])
    }

    @Test func itRoundTripsThroughJSON() throws {
        var dismissal = ReflectDismissal()
        dismissal.dismiss("generated:0", for: "month:200")

        let data = try JSONEncoder().encode(dismissal)
        #expect(try JSONDecoder().decode(ReflectDismissal.self, from: data) == dismissal)
    }
}
