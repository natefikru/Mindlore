import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct AnswerFeedbackTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    @Test func aSecondTapOnTheSameVerdictClearsIt() {
        let key = UUID().uuidString
        #expect(AnswerFeedback.verdict(on: key, surface: .ask, in: context) == nil)
        #expect(AnswerFeedback.toggle(.up, on: key, surface: .ask, in: context) == .up)
        #expect(AnswerFeedback.verdict(on: key, surface: .ask, in: context) == .up)
        #expect(AnswerFeedback.toggle(.up, on: key, surface: .ask, in: context) == nil)
        #expect(AnswerFeedback.verdict(on: key, surface: .ask, in: context) == nil)
    }

    @Test func theOtherVerdictReplacesTheFirst() {
        let key = UUID().uuidString
        #expect(AnswerFeedback.toggle(.up, on: key, surface: .ask, in: context) == .up)
        #expect(AnswerFeedback.toggle(.down, on: key, surface: .ask, in: context) == .down)
        #expect(AnswerFeedback.verdict(on: key, surface: .ask, in: context) == .down)
    }

    @Test func oneRowHoldsEveryVerdictForASurface() {
        AnswerFeedback.toggle(.up, on: "a", surface: .ask, in: context)
        AnswerFeedback.toggle(.down, on: "b", surface: .ask, in: context)
        AnswerFeedback.toggle(.up, on: "c", surface: .ask, in: context)
        #expect(AnswerFeedback.rows(.ask, in: context).count == 1)
        #expect(AnswerFeedback.verdict(on: "a", surface: .ask, in: context) == .up)
        #expect(AnswerFeedback.verdict(on: "b", surface: .ask, in: context) == .down)
    }

    @Test func askAndInsightsFeedbackAreKeptApart() {
        let key = UUID().uuidString
        AnswerFeedback.toggle(.up, on: key, surface: .ask, in: context)
        #expect(AnswerFeedback.verdict(on: key, surface: .insights, in: context) == nil)
        AnswerFeedback.toggle(.down, on: key, surface: .insights, in: context)
        #expect(AnswerFeedback.verdict(on: key, surface: .ask, in: context) == .up)
        #expect(AnswerFeedback.verdict(on: key, surface: .insights, in: context) == .down)
    }
}

// The verdict and the surface only; the key that identifies which answer or entry it belongs to
// never carries user text (it is always a UUID), but the event fields are checked anyway, the same
// way every other diagnostics path is.
@MainActor
struct AnswerFeedbackDiagnosticsPrivacyTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let sentinel = DiagnosticsPrivacyTests.sentinel

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    @Test func theLogCarriesTheVerdictAndTheSurfaceOnly() {
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)
        let key = UUID().uuidString

        AnswerFeedback.toggle(.up, on: key, surface: .ask, in: context, diagnostics: log)
        AnswerFeedback.toggle(.down, on: sentinel, surface: .insights, in: context, diagnostics: log)
        AnswerFeedback.toggle(.down, on: sentinel, surface: .insights, in: context, diagnostics: log)

        let contents = file.contents()
        #expect(contents.contains("ask.feedback"))
        #expect(contents.contains("insights.feedback"))
        #expect(contents.contains(sentinel) == false)
    }
}
