import Foundation
import SwiftData
import Testing
@testable import Mindlore

private let day: TimeInterval = 86_400

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

// The pure half of Reflect's Loose ends tab: order, months, filters, and the words on a row.
struct ReflectLooseEndsTests {
    private let english = Locale(identifier: "en_US")

    @Test func newestRaisedFirstAndTiesNeverShuffle() {
        let old = ReflectLooseEnds.Item(text: "old", raisedOn: date(2026, 1, 4))
        let newest = ReflectLooseEnds.Item(text: "newest", status: .resolved, raisedOn: date(2026, 9, 20))
        let sameDayB = ReflectLooseEnds.Item(text: "b", raisedOn: date(2026, 5, 1))
        let sameDayA = ReflectLooseEnds.Item(text: "a", status: .faded, raisedOn: date(2026, 5, 1))

        let ordered = ReflectLooseEnds.ordered([old, sameDayB, newest, sameDayA])
        #expect(ordered.map(\.text) == ["newest", "a", "b", "old"])
        #expect(ReflectLooseEnds.ordered(ordered.reversed()) == ordered)
    }

    // Closing or reopening one changes its status date, never its place: it sits with the day it
    // was raised.
    @Test func closingOneDoesNotMoveIt() {
        let early = ReflectLooseEnds.Item(text: "early", status: .resolved, raisedOn: date(2026, 3, 1), statusChangedAt: date(2026, 9, 21), userTouched: true)
        let late = ReflectLooseEnds.Item(text: "late", raisedOn: date(2026, 6, 1))
        #expect(ReflectLooseEnds.ordered([early, late]).map(\.text) == ["late", "early"])
    }

    @Test func monthsFollowTheRaisedDateAndTheFilter() {
        let items = [
            ReflectLooseEnds.Item(text: "open sep", raisedOn: date(2026, 9, 3)),
            ReflectLooseEnds.Item(text: "done sep", status: .resolved, raisedOn: date(2026, 9, 1)),
            ReflectLooseEnds.Item(text: "faded aug", status: .faded, raisedOn: date(2026, 8, 20)),
            ReflectLooseEnds.Item(text: "let go jun", status: .dismissed, raisedOn: date(2026, 6, 2)),
            ReflectLooseEnds.Item(text: "open jun", raisedOn: date(2026, 6, 30)),
        ]

        let all = ReflectLooseEnds.months(items, filter: .all, calendar: utc)
        #expect(all.map(\.start) == [date(2026, 9, 1, hour: 0), date(2026, 8, 1, hour: 0), date(2026, 6, 1, hour: 0)])
        #expect(all.map { $0.items.map(\.text) } == [["open sep", "done sep"], ["faded aug"], ["open jun", "let go jun"]])

        let open = ReflectLooseEnds.months(items, filter: .open, calendar: utc)
        #expect(open.flatMap(\.items).map(\.text) == ["open sep", "open jun"])

        let closed = ReflectLooseEnds.months(items, filter: .closed, calendar: utc)
        #expect(closed.flatMap(\.items).map(\.text) == ["done sep", "faded aug", "let go jun"], "closed is every ending")

        #expect(ReflectLooseEnds.filtered(items, by: .all).count == 5)
        #expect(ReflectLooseEnds.months([], filter: .all, calendar: utc).isEmpty)
    }

    @Test func openOnesArePinnedAboveTheMonthsDueSoonestFirst() {
        let items = [
            ReflectLooseEnds.Item(text: "open new", raisedOn: date(2026, 9, 10)),
            ReflectLooseEnds.Item(text: "done sep", status: .resolved, raisedOn: date(2026, 9, 12)),
            ReflectLooseEnds.Item(text: "open old due late", raisedOn: date(2026, 5, 1), dueDate: date(2026, 10, 30)),
            ReflectLooseEnds.Item(text: "open due soon", raisedOn: date(2026, 8, 1), dueDate: date(2026, 9, 28)),
            ReflectLooseEnds.Item(text: "open older", raisedOn: date(2026, 6, 1)),
            ReflectLooseEnds.Item(text: "faded aug", status: .faded, raisedOn: date(2026, 8, 20)),
        ]

        let all = ReflectLooseEnds.layout(items, filter: .all, calendar: utc)
        #expect(all.open.map(\.text) == ["open due soon", "open old due late", "open new", "open older"])
        #expect(all.months.flatMap(\.items).map(\.text) == ["done sep", "faded aug"], "an open one never repeats below")

        let open = ReflectLooseEnds.layout(items, filter: .open, calendar: utc)
        #expect(open.open.count == 4)
        #expect(open.months.isEmpty)

        let closed = ReflectLooseEnds.layout(items, filter: .closed, calendar: utc)
        #expect(closed.open.isEmpty)
        #expect(closed.months.flatMap(\.items).map(\.text) == ["done sep", "faded aug"])

        #expect(ReflectLooseEnds.layout([], filter: .all, calendar: utc).isEmpty)
    }

    @Test func eachStatusHasItsOwnWordAndShape() {
        let statuses = LooseEndStatus.allCases
        #expect(statuses.map(ReflectLooseEnds.statusTitle) == ["Open", "Done", "Faded", "Let go"])
        #expect(Set(statuses.map(ReflectLooseEnds.symbol)).count == statuses.count, "never colour alone")
    }

    @Test func theDetailLineSaysWhenItWasRaisedAndHowItEnded() {
        func detail(_ item: ReflectLooseEnds.Item) -> String {
            ReflectLooseEnds.detail(item, calendar: utc, locale: english)
        }
        let raised = date(2026, 9, 3)
        #expect(detail(.init(text: "t", raisedOn: raised, dueDate: date(2026, 9, 30))) == "Raised Sep 3 \u{00B7} due Sep 30")
        #expect(detail(.init(text: "t", status: .resolved, raisedOn: raised, statusChangedAt: date(2026, 9, 20), userTouched: true)) == "Raised Sep 3 \u{00B7} done Sep 20")
        #expect(detail(.init(text: "t", status: .resolved, raisedOn: raised, statusChangedAt: date(2026, 9, 20))) == "Raised Sep 3 \u{00B7} settled by a later entry Sep 20")
        #expect(detail(.init(text: "t", status: .faded, raisedOn: raised, statusChangedAt: date(2026, 10, 15))) == "Raised Sep 3 \u{00B7} faded Oct 15")
        #expect(detail(.init(text: "t", status: .dismissed, raisedOn: raised, statusChangedAt: date(2026, 9, 4), userTouched: true)) == "Raised Sep 3 \u{00B7} let go Sep 4")
        #expect(detail(.init(text: "t", raisedOn: raised, statusChangedAt: date(2026, 9, 22), userTouched: true)) == "Raised Sep 3 \u{00B7} reopened Sep 22")
        #expect(detail(.init(text: "t", raisedOn: date(2026, 12, 30), dueDate: date(2027, 1, 5))) == "Raised Dec 30 \u{00B7} due Jan 5, 2027", "another year names itself")
        #expect(ReflectLooseEnds.monthTitle(date(2026, 9, 1, hour: 0), calendar: utc, locale: english) == "September 2026")
    }

    @Test func onlyAReopenedOneReadsAsReopened() {
        let reopened = ReflectLooseEnds.Item(text: "t", raisedOn: date(2026, 9, 1), statusChangedAt: date(2026, 9, 5), userTouched: true)
        let settledThenRolledBack = ReflectLooseEnds.Item(text: "t", raisedOn: date(2026, 9, 1), statusChangedAt: date(2026, 9, 5))
        #expect(reopened.reopenedAt == date(2026, 9, 5) && reopened.closedAt == nil)
        #expect(settledThenRolledBack.reopenedAt == nil)
    }
}

// The store half: merges, hidden names, the three actions, and the reopen rule they rely on.
@MainActor
struct ReflectLooseEndSourceTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    @discardableResult
    private func entity(_ name: String) throws -> Entity {
        let entity = Entity(name: name, key: name.lowercased(), kind: .person)
        context.insert(entity)
        try context.save()
        return entity
    }

    @discardableResult
    private func looseEnd(_ text: String, raised: Date = date(2026, 9, 1), about: [UUID] = [], due: Date? = nil) throws -> LooseEnd {
        let end = LooseEnd(text: text, sourceEntryID: UUID(), sourceEntryDate: raised, entityIDs: about, dueDate: due)
        context.insert(end)
        try context.save()
        return end
    }

    @Test func itemsWalkMergesAndLeaveOutAnythingAboutAHiddenName() throws {
        let winner = try entity("Sarah Kim")
        let loser = try entity("S. Kim")
        loser.mergedIntoID = winner.id
        let hidden = try entity("Hidden Person")
        hidden.hidden = true
        let muted = try entity("Muted Person")
        muted.resurfacingMuted = true
        try looseEnd("Hear back from Sarah", about: [loser.id, winner.id])
        try looseEnd("Call the hidden one", about: [hidden.id, winner.id])
        try looseEnd("Ask the muted one", about: [muted.id])
        try looseEnd("About nobody")
        try context.save()

        let items = ReflectLooseEndSource.items(in: context)
        let byText = Dictionary(uniqueKeysWithValues: items.map { ($0.text, $0) })
        #expect(byText["Hear back from Sarah"]?.subjects == ["Sarah Kim"], "the merge walked, and named once")
        #expect(byText["Call the hidden one"] == nil, "its text is about someone hidden, so the row goes whole")
        #expect(byText["Ask the muted one"]?.subjects == ["Muted Person"], "muting is about Today, not history")
        #expect(byText["About nobody"]?.subjects == [])
        #expect(!items.contains { $0.subjects.contains("Hidden Person") })
    }

    @Test func everyStatusIsListed() throws {
        let open = try looseEnd("open")
        let done = try looseEnd("done")
        done.setByUser(.resolved)
        let faded = try looseEnd("faded")
        faded.setStatus(.faded, at: date(2026, 9, 20))
        let letGo = try looseEnd("let go")
        letGo.setByUser(.dismissed)
        try context.save()

        let items = ReflectLooseEndSource.items(in: context)
        #expect(Set(items.map(\.status)) == Set(LooseEndStatus.allCases))
        #expect(items.first { $0.id == open.id }?.raisedOn == date(2026, 9, 1))
    }

    @Test func eachActionFitsOnlyItsStatus() throws {
        let end = try looseEnd("call the landlord")
        #expect(!ReflectLooseEndSource.apply(.reopen, to: end.id, in: context, diagnostics: .disabled), "already open")
        #expect(ReflectLooseEndSource.apply(.done, to: end.id, in: context, diagnostics: .disabled))
        #expect(end.status == .resolved && end.userTouched)
        #expect(!ReflectLooseEndSource.apply(.letGo, to: end.id, in: context, diagnostics: .disabled), "already closed")
        #expect(ReflectLooseEndSource.apply(.reopen, to: end.id, in: context, diagnostics: .disabled))
        #expect(end.isOpen)
        #expect(ReflectLooseEndSource.apply(.letGo, to: end.id, in: context, diagnostics: .disabled))
        #expect(end.status == .dismissed)
        #expect(!ReflectLooseEndSource.apply(.done, to: UUID(), in: context, diagnostics: .disabled), "gone")
    }

    // The reopen rule: open, the user's own, and a fresh clock, so the next launch sweep leaves it.
    @Test func aReopenedDatedOneLongPastItsDaySurvivesTheNextSweep() throws {
        let end = try looseEnd("interview", raised: date(2026, 3, 1), due: date(2026, 3, 10))
        #expect(LooseEnd.fade(in: context, now: date(2026, 4, 1), diagnostics: .disabled) == 1)
        #expect(end.status == .faded)

        let reopened = date(2026, 9, 20)
        #expect(ReflectLooseEndSource.apply(.reopen, to: end.id, in: context, now: reopened, diagnostics: .disabled))
        #expect(end.isOpen && end.userTouched)
        #expect(end.statusChangedAt == reopened && end.reopenedAt == reopened)
        #expect(end.lastMentionedAt == reopened)

        #expect(LooseEnd.fade(in: context, now: reopened.addingTimeInterval(day), diagnostics: .disabled) == 0)
        #expect(end.isOpen, "the sweep right after a reopen leaves it open")
        #expect(LooseEnd.fade(in: context, now: reopened.addingTimeInterval(8 * day), diagnostics: .disabled) == 1, "then a week, like a dated one past its day")
    }

    @Test func aReopenedUndatedOneGetsSixWeeksAgain() throws {
        let end = try looseEnd("hear from Acme", raised: date(2026, 1, 1))
        #expect(LooseEnd.fade(in: context, now: date(2026, 3, 1), diagnostics: .disabled) == 1)

        let reopened = date(2026, 9, 1)
        #expect(ReflectLooseEndSource.apply(.reopen, to: end.id, in: context, now: reopened, diagnostics: .disabled))
        #expect(LooseEnd.fade(in: context, now: reopened.addingTimeInterval(41 * day), diagnostics: .disabled) == 0)
        #expect(LooseEnd.fade(in: context, now: reopened.addingTimeInterval(43 * day), diagnostics: .disabled) == 1)
    }

    // A reopen never shortens the time a thread still had: a due date after the reopen still rules.
    @Test func aReopenBeforeItsDayKeepsItsDay() throws {
        let end = try looseEnd("wedding", raised: date(2026, 9, 1), due: date(2026, 12, 1))
        end.setByUser(.dismissed, at: date(2026, 9, 2))
        end.setByUser(.open, at: date(2026, 9, 3))
        #expect(end.fadeDate == date(2026, 12, 8))
    }

    // Today's thread card names the same fade date the sweep uses, reopen included.
    @Test func todaysCardAgreesWithTheSweepAfterAReopen() throws {
        let end = try looseEnd("interview", raised: date(2026, 3, 1), due: date(2026, 3, 10))
        end.setByUser(.dismissed, at: date(2026, 3, 2))
        end.setByUser(.open, at: date(2026, 9, 20))
        let facts = LooseEndFacts(id: end.id, text: end.text, sourceEntryDate: end.sourceEntryDate, lastMentionedAt: end.lastMentionedAt, dueDate: end.dueDate, reopenedAt: end.reopenedAt)
        #expect(facts.fadeDate == end.fadeDate)
        #expect(!LooseEnd.shouldFade(end, now: facts.fadeDate))
        #expect(LooseEnd.shouldFade(end, now: facts.fadeDate.addingTimeInterval(1)))
    }

    @Test func theLogSaysWhatWasDoneAndNeverWhatItWasAbout() throws {
        let sentinel = DiagnosticsPrivacyTests.sentinel
        let who = try entity(sentinel)
        let end = try looseEnd("call \(sentinel)", about: [who.id])
        #expect(ReflectLooseEndSource.items(in: context).first?.subjects == [sentinel], "the sentinel really is on the row")

        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)
        #expect(ReflectLooseEndSource.apply(.done, to: end.id, in: context, diagnostics: log))
        #expect(ReflectLooseEndSource.apply(.reopen, to: end.id, in: context, diagnostics: log))
        #expect(ReflectLooseEndSource.apply(.letGo, to: end.id, in: context, diagnostics: log))

        let contents = file.contents()
        #expect(contents.contains("reflect.looseEnd"))
        #expect(contents.contains("reopen"))
        #expect(!contents.contains(sentinel))
    }
}
