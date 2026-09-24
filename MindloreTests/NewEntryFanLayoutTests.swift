import CoreGraphics
import Testing
@testable import Mindlore

struct NewEntryFanLayoutTests {
    private let plus = CGPoint(x: 200, y: 800)
    private let all = NewEntryFanLayout.options(pagesAvailable: true)

    @Test func theOptionsSitOnAHalfCircleAboveThePlusRecordOnTop() {
        let centers = NewEntryFanLayout.centers(around: plus, options: all)
        let write = centers[.write]!, record = centers[.record]!, pages = centers[.pages]!
        #expect(write.x < record.x && record.x < pages.x, "left to right: Write, Record, Pages")
        #expect(record.y < write.y && record.y < pages.y, "Record is the top of the arc")
        #expect(abs(record.x - plus.x) < 0.001)
        for center in [write, record, pages] {
            #expect(center.y < plus.y, "every option is above the +")
            let arcCentre = CGPoint(x: plus.x, y: plus.y - NewEntryFanLayout.lift)
            #expect(abs(NewEntryFanLayout.distance(center, arcCentre) - NewEntryFanLayout.radius) < 0.001)
        }
    }

    @Test func withoutACameraTheTwoSpreadToTheEndsOfTheArc() {
        let two = NewEntryFanLayout.options(pagesAvailable: false)
        #expect(two == [.write, .record])
        let centers = NewEntryFanLayout.centers(around: plus, options: two)
        #expect(centers[.write]!.x < plus.x && centers[.record]!.x > plus.x)
        #expect(abs(centers[.write]!.y - centers[.record]!.y) < 0.001)
    }

    @Test func aPointIsOnTheNearestOptionWithinReachAndOnNothingBetween() {
        let centers = NewEntryFanLayout.centers(around: plus, options: all)
        let record = centers[.record]!
        #expect(NewEntryFanLayout.option(at: record, plus: plus, options: all) == .record)
        #expect(NewEntryFanLayout.option(at: CGPoint(x: record.x + 30, y: record.y + 20), plus: plus, options: all) == .record)
        #expect(NewEntryFanLayout.option(at: plus, plus: plus, options: all) == nil, "the + itself is no option")
        #expect(NewEntryFanLayout.option(at: CGPoint(x: plus.x, y: plus.y + 40), plus: plus, options: all) == nil, "below the arc")
        #expect(NewEntryFanLayout.option(at: CGPoint(x: plus.x, y: plus.y - 300), plus: plus, options: all) == nil, "far above")
    }

    @Test func releasingOnAnOptionChoosesItWhateverOpenedTheFan() {
        let pages = NewEntryFanLayout.centers(around: plus, options: all)[.pages]!
        #expect(NewEntryFanLayout.release(at: pages, plus: plus, options: all, leftPlus: true, openedByThisTouch: true) == .choose(.pages))
        #expect(NewEntryFanLayout.release(at: pages, plus: plus, options: all, leftPlus: true, openedByThisTouch: false) == .choose(.pages))
    }

    @Test func aTapThatOpenedTheFanLeavesItOpen() {
        let nudge = CGPoint(x: plus.x + 4, y: plus.y - 3)
        #expect(NewEntryFanLayout.release(at: nudge, plus: plus, options: all, leftPlus: false, openedByThisTouch: true) == .stayOpen)
    }

    @Test func aTouchThatWanderedOffAndCameBackStillCloses() {
        #expect(NewEntryFanLayout.release(at: plus, plus: plus, options: all, leftPlus: true, openedByThisTouch: true) == .close)
    }

    @Test func aTouchOnThePlusWhileOpenClosesIt() {
        #expect(NewEntryFanLayout.release(at: plus, plus: plus, options: all, leftPlus: false, openedByThisTouch: false) == .close)
    }

    @Test func lettingGoAnywhereElseCloses() {
        let away = CGPoint(x: 40, y: 500)
        #expect(NewEntryFanLayout.release(at: away, plus: plus, options: all, leftPlus: true, openedByThisTouch: true) == .close)
    }
}
