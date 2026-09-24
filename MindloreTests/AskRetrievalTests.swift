import Foundation
import Testing
@testable import Mindlore

struct AskRetrievalTests {
    // Monday 14 September 2026, 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_394_400)

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private let maya = UUID()

    private func id(for name: String) -> UUID {
        var bytes = Array(name.utf8.prefix(16))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16 - bytes.count))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func input(
        _ name: String,
        text: String = "the deadline moved",
        daysAgo: Int = 0,
        entityNames: [String] = [],
        isSendable: Bool = true,
        blockCharacters: Int = 1_000
    ) -> AskIndex.DocumentInput {
        AskIndex.DocumentInput(
            id: id(for: name),
            date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            text: text,
            entityNames: entityNames,
            isSendable: isSendable,
            blockCharacters: blockCharacters
        )
    }

    private func index(_ inputs: [AskIndex.DocumentInput]) -> AskIndex {
        AskIndex.build(from: inputs, entities: [AskIndex.Entity(id: maya, name: "Maya", kindRaw: "person")])
    }

    private func query(_ question: String, previous: [String] = [], cited: [[UUID]] = [], in index: AskIndex) -> AskRetrievalQuery {
        AskRetrievalQuery.build(
            question: question,
            previousQuestions: previous,
            citedEntryIDs: cited,
            index: index,
            now: now,
            calendar: calendar
        )
    }

    private func plan(
        _ question: String,
        previous: [String] = [],
        cited: [[UUID]] = [],
        in index: AskIndex,
        budget: Int = AskContextBuilder.openAIBudget,
        provider: AskProviderKind = .openAI,
        rollups: Bool = false
    ) -> AskRetrieval.Plan {
        AskRetrieval.plan(
            query: query(question, previous: previous, cited: cited, in: index),
            index: index,
            budget: budget,
            provider: provider,
            rollups: rollups,
            calendar: calendar
        )
    }

    // MARK: - Slices

    @Test func openAISlicesLeaveRankedMostOfTheBudget() {
        let slices = AskRetrieval.slices(budget: AskContextBuilder.openAIBudget, provider: .openAI)
        #expect(slices.about == 3_600)
        #expect(slices.rollups == 6_000)
        #expect(slices.digests == 24_020, "exactly 150 lines at their worst")
        #expect(slices.continuity == 4_800)
        #expect(slices.ranked == 25_580)
        #expect(slices.total == AskContextBuilder.openAIBudget)
    }

    @Test func onDeviceGetsAboutBlocksAndEntriesAndNothingElse() {
        // The real on-device budget, near 3,300 after the system prompt and answer headroom. A 20%
        // continuity slice would be 660 characters, which no entry block fits into.
        let slices = AskRetrieval.slices(budget: 3_300, provider: .onDevice)
        #expect(slices.about == 800)
        #expect(slices.rollups == 0)
        #expect(slices.digests == 0)
        #expect(slices.continuity == 0)
        #expect(slices.ranked == 2_500)
        #expect(slices.total == 3_300)
    }

    @Test func aTinyBudgetNeverGoesNegative() {
        let slices = AskRetrieval.slices(budget: 500, provider: .openAI)
        #expect(slices.total == 500)
        #expect(slices.ranked >= 0)
        #expect(AskRetrieval.slices(budget: 0, provider: .openAI) == AskRetrieval.Slices())
    }

    // MARK: - Ranking and the caps

    @Test func rankedStopsAtTheProvidersLimit() {
        let inputs = (0..<30).map { input("entry\($0)", daysAgo: $0, blockCharacters: 100) }
        let result = plan("deadline", in: index(inputs))
        #expect(result.rankedEntryIDs.count == AskRetrieval.maxRankedEntriesOpenAI)
        // Budget alone would have taken all thirty at 100 characters each. The k is the second brake.
        #expect(result.matchedCount == 30)
    }

    @Test func onDeviceTakesFive() {
        let inputs = (0..<30).map { input("entry\($0)", daysAgo: $0, blockCharacters: 100) }
        let result = plan("deadline", in: index(inputs), budget: 3_300, provider: .onDevice)
        #expect(result.rankedEntryIDs.count == AskRetrieval.maxRankedEntriesOnDevice)
    }

    @Test func aBlockTooBigToFitIsSkippedAndASmallerOneStillGoes() {
        let inputs = [
            input("huge", daysAgo: 0, blockCharacters: 100_000),
            input("small", daysAgo: 1, blockCharacters: 200),
        ]
        let result = plan("deadline", in: index(inputs))
        #expect(result.rankedEntryIDs == [id(for: "small")])
    }

    @Test func rankedIsCappedByWhatTheBudgetActuallyFits() {
        // Forty entries at 2,050 characters is 82,000, against a budget of 20,000 that has already
        // held back room for the digests. Twenty would otherwise go, so it is the budget and not
        // the cap that decides here.
        let inputs = (0..<40).map { input("entry\($0)", daysAgo: $0, blockCharacters: 2_050) }
        let result = plan("deadline", in: index(inputs), budget: 20_000)
        #expect(result.rankedEntryIDs.count < AskRetrieval.maxRankedEntriesOpenAI)
        #expect(result.estimatedCharacters <= 20_000)
    }

    // MARK: - matchedCount

    @Test func anEntryLinkedToWhatWasAskedAboutCountsAsMatching() {
        // One entry writes "deadline" four times; twenty are linked to the Deadline Project without
        // saying the word. All twenty-one count, because all twenty-one really are about it. The
        // strong one still leads, which is the part the old keyword counting got wrong.
        var inputs = [input("strong", text: "deadline deadline deadline the deadline moved again")]
        inputs += (0..<20).map { input("weak\($0)", text: "a day at work", daysAgo: $0 + 1, entityNames: ["Deadline Project"]) }
        let result = plan("deadline", in: index(inputs))
        #expect(result.matchedCount == 21)
        #expect(result.rankedEntryIDs.first == id(for: "strong"))
        // Twenty went whole and the twenty-first went as a line, so nothing was left behind and
        // the prompt has nothing to own up to. Before the digest tier this was a cut.
        #expect(result.digestEntryIDs.count == 1)
        #expect(result.wasCut == false)
    }

    @Test func anEntryThatOnlyBrushedTheQuestionIsNotCounted() {
        // "work" is in every entry, so its IDF is near zero; "ayahuasca" is in one. The floor is
        // what stops the twenty from padding the denominator of a question they barely touch.
        var inputs = [input("strong", text: "the ayahuasca retreat and more work")]
        inputs += (0..<20).map { input("weak\($0)", text: "another day of work", daysAgo: $0 + 1) }
        let result = plan("ayahuasca work", in: index(inputs))
        #expect(result.matchedCount < 21)
        #expect(result.rankedEntryIDs.first == id(for: "strong"))
    }

    @Test func aQuestionAboutAPeriodIsMeasuredAgainstThePeriod() {
        // The failure mode this phase exists to kill. Three hundred entries this year, and the
        // question shares a word with almost none of them. Counting term matches alone reports
        // "12 of 12" and the model answers the year from two weeks with nothing telling it not to.
        let inputs = (0..<300).map { input("entry\($0)", text: "an ordinary day", daysAgo: $0, blockCharacters: 1_000) }
        let result = plan("How have I been feeling this year?", in: index(inputs), rollups: true)
        #expect(result.appliedRange != nil)
        #expect(result.matchedCount > 200)
        #expect(result.rankedEntryIDs.count <= AskRetrieval.maxRankedEntriesOpenAI)
        // The year arrives as lines. Two hundred of them still don't, which is what the cut note
        // is for.
        #expect(result.digestEntryIDs.count == AskRetrieval.maxDigestEntries)
        #expect(result.wasCut)
        // And a set that much larger than the cut is an aggregate question whatever its wording,
        // so the rollup goes in beside the sample.
        #expect(result.isAggregate)
        #expect(result.rollupMonths.isEmpty == false)
    }

    @Test func wasCutIsFalseWhenEverythingMatchedWentIn() {
        let result = plan("deadline", in: index([input("a", blockCharacters: 100)]))
        #expect(result.matchedCount == 1)
        #expect(result.wasCut == false)
    }

    @Test func wasCutIsTrueWhenTheListWasTrimmed() {
        // Twenty whole and a hundred and fifty lines cover a hundred and seventy of them; the rest
        // are what a cut is now.
        let inputs = (0..<200).map { input("entry\($0)", daysAgo: $0, blockCharacters: 100) }
        #expect(plan("deadline", in: index(inputs)).wasCut)
    }

    // MARK: - Aggregate

    @Test func aMarkerMakesAQuestionAggregate() {
        let result = plan("How often does the deadline move?", in: index([input("a", blockCharacters: 100)]), rollups: true)
        #expect(result.isAggregate)
        #expect(result.rollupMonths.isEmpty == false)
    }

    @Test func aMatchedSetFarLargerThanTheCutIsAggregateWhateverTheWording() {
        let inputs = (0..<(AskRetrieval.aggregateMatchCount + 5)).map { input("entry\($0)", daysAgo: $0, blockCharacters: 100) }
        let result = plan("what did I write about the deadline", in: index(inputs))
        #expect(result.isAggregate)
    }

    @Test func anOrdinaryQuestionGetsNoRollups() {
        let result = plan("deadline", in: index([input("a", blockCharacters: 100)]), rollups: true)
        #expect(result.isAggregate == false)
        #expect(result.rollupMonths.isEmpty)
    }

    @Test func rollupMonthsAreDistinctNewestFirstAndFitTheirSlice() {
        // Three years of entries, one a month. All thirty-six survive, because past two years the
        // lines become years and the reserve knows it: capping the plan at twenty-four instead threw
        // the oldest twelve months away and made the year path unreachable.
        let inputs = (0..<36).map { input("entry\($0)", daysAgo: $0 * 31, blockCharacters: 100) }
        let result = plan("how often did the deadline move", in: index(inputs), rollups: true)
        #expect(result.rollupMonths.count == 36)
        #expect(result.rollupMonths == result.rollupMonths.sorted { $0.start > $1.start })
        #expect(Set(result.rollupMonths.map(\.start)).count == result.rollupMonths.count)
        #expect(AskRollups.estimatedCharacters(monthCount: result.rollupMonths.count) <= result.slices.rollups)
    }

    // The months have to describe the same set the number beside them describes, or the summary
    // contradicts the sentence above it in the same prompt.
    @Test func theRollupCountsTheSameEntriesMatchedCountDoes() {
        let inputs = (0..<40).map { input("entry\($0)", text: $0 < 10 ? "the deadline moved" : "something else", daysAgo: $0 * 3, blockCharacters: 100) }
        let result = plan("how often did the deadline move", in: index(inputs), rollups: true)
        let months = AskRollups.months(for: result.rollupMonths, matching: result.matchedEntryIDs, in: index(inputs), calendar: calendar)
        #expect(months.reduce(0) { $0 + $1.count } == result.matchedCount)
    }

    @Test func rollupsAreNotPlannedUntilSomethingRendersThem() {
        // PR 2 renders them. Planning them before that reserves and reports characters that never
        // leave the phone, and sets a summary count for a summary that does not exist.
        let inputs = (0..<60).map { input("entry\($0)", daysAgo: $0, blockCharacters: 100) }
        #expect(plan("how often did the deadline move", in: index(inputs)).rollupMonths.isEmpty)
    }

    @Test func onDeviceGetsNoRollupsEvenForAnAggregateQuestion() {
        let inputs = (0..<36).map { input("entry\($0)", daysAgo: $0 * 31, blockCharacters: 100) }
        let result = plan("how often did the deadline move", in: index(inputs), budget: 3_300, provider: .onDevice, rollups: true)
        #expect(result.isAggregate)
        #expect(result.rollupMonths.isEmpty)
    }

    // MARK: - Continuity

    @Test func theConversationsOwnEntriesComeBackFromTheirOwnSlice() {
        let inputs = [
            input("new", text: "deadline", daysAgo: 0, blockCharacters: 500),
            input("cited", text: "nothing to do with it", daysAgo: 40, blockCharacters: 500),
        ]
        let result = plan("deadline", cited: [[id(for: "cited")]], in: index(inputs))
        #expect(result.rankedEntryIDs == [id(for: "new")])
        #expect(result.continuityEntryIDs == [id(for: "cited")])
        #expect(result.entryIDs.count == 2)
    }

    @Test func anEntryTheRankedListAlreadyTookIsNotSentTwice() {
        let inputs = [input("both", text: "deadline", blockCharacters: 500)]
        let result = plan("deadline", cited: [[id(for: "both")]], in: index(inputs))
        #expect(result.rankedEntryIDs == [id(for: "both")])
        #expect(result.continuityEntryIDs.isEmpty)
    }

    @Test func continuityCannotEatTheRankedSlice() {
        // Twenty cited entries at 500 characters is 10,000, more than the 4,800 continuity slice.
        let cited = (0..<20).map { id(for: "cited\($0)") }
        var inputs = [input("new", text: "deadline", blockCharacters: 500)]
        inputs += (0..<20).map { input("cited\($0)", text: "unrelated", daysAgo: 100 + $0, blockCharacters: 500) }
        let result = plan("deadline", cited: [cited], in: index(inputs))
        let continuityCharacters = result.continuityEntryIDs.count * 502
        #expect(continuityCharacters <= AskRetrieval.continuityBudgetOpenAI)
        #expect(result.rankedEntryIDs.contains(id(for: "new")))
    }

    @Test func aCitedEntryThatMayNotBeSentNeverComesBack() {
        let inputs = [
            input("new", text: "deadline", blockCharacters: 500),
            input("held", text: "unrelated", daysAgo: 5, isSendable: false, blockCharacters: 500),
        ]
        let result = plan("deadline", cited: [[id(for: "held")]], in: index(inputs))
        #expect(result.continuityEntryIDs.isEmpty)
    }

    // MARK: - Excerpts

    // The old tier 1's rule, and the one an earlier pass inverted. An entry reached through the
    // person the question names is quoted at the sentences about her, so ten fit where three whole
    // blocks would. Keying it off "no query term in the body" made the set the entries that never
    // mention her, whose naming sentences do not exist, so it fired only where it should not have.
    @Test func anEntryLinkedToTheEntityTheQuestionNamesIsMarkedForExcerpting() {
        let inputs = [
            input("names-her", text: "Long day. Maya came by at lunch and stayed an hour.", entityNames: ["Maya"]),
            input("unrelated", text: "the deadline moved", daysAgo: 3),
        ]
        var index = AskIndex.build(from: inputs, entities: [AskIndex.Entity(id: maya, name: "Maya", kindRaw: "person")])
        // The entity id has to be the one the documents carry, so rebuild with it linked.
        index = AskIndex.build(
            from: [
                AskIndex.DocumentInput(id: id(for: "names-her"), date: now, text: "Long day. Maya came by at lunch and stayed an hour.", entityIDs: [maya], entityNames: ["Maya"], blockCharacters: 200),
                inputs[1],
            ],
            entities: [AskIndex.Entity(id: maya, name: "Maya", kindRaw: "person")]
        )

        let result = plan("What's going on with Maya?", in: index)
        #expect(result.rankedEntryIDs.contains(id(for: "names-her")))
        #expect(result.excerptEntryIDs.contains(id(for: "names-her")))
    }

    @Test func anEntryTheQuestionNamesNobodyInIsNeverExcerpted() {
        let index = index([input("a", text: "the deadline moved", blockCharacters: 200)])
        let result = plan("deadline", in: index)
        #expect(result.rankedEntryIDs == [id(for: "a")])
        #expect(result.excerptEntryIDs.isEmpty)
    }

    // MARK: - About blocks and ranges

    @Test func namedAndCarriedEntitiesBothGetDescribed() {
        let result = plan("Why did that start?", previous: ["What's going on with Maya?"], in: index([input("a", blockCharacters: 100)]))
        #expect(result.aboutEntityIDs == [maya])
    }

    @Test func theAppliedRangeSaysWhetherItWasInherited() {
        // Dated inside last week, or the range matches nothing, the recency fallback fires, and the
        // plan correctly reports no range at all.
        let journal = index([input("a", daysAgo: 3, blockCharacters: 100)])
        let named = plan("What did I do last week?", in: journal)
        #expect(named.appliedRange != nil)
        #expect(named.rangeWasInherited == false)

        let inherited = plan("What about the deadline then?", previous: ["What did I do last week?"], in: journal)
        #expect(inherited.appliedRange != nil)
        #expect(inherited.rangeWasInherited)
    }

    // MARK: - What the About blocks reserve

    @Test func anAboutBlockReservesWhatItWillTakeNotTheWholeSlice() {
        let small = AskIndex.Entity(id: maya, name: "Maya", kindRaw: "person", aboutCharacters: 120)
        let index = AskIndex.build(from: [input("a", blockCharacters: 2_050)], entities: [small])
        let reserve = AskRetrieval.aboutReserve(
            for: [maya],
            in: index,
            slices: AskRetrieval.slices(budget: AskContextBuilder.openAIBudget, provider: .openAI),
            budget: AskContextBuilder.openAIBudget
        )
        // Reserving the whole 3,600 slice for a 120-character block cost two ranked entries on the
        // commonest question shape there is.
        #expect(reserve < 200)
    }

    @Test func aHugeAboutBlockIsStillCappedBySliceAndBudget() {
        let huge = AskIndex.Entity(id: maya, name: "Maya", kindRaw: "person", aboutCharacters: 100_000)
        let index = AskIndex.build(from: [input("a", blockCharacters: 100)], entities: [huge])

        let slices = AskRetrieval.slices(budget: AskContextBuilder.openAIBudget, provider: .openAI)
        #expect(AskRetrieval.aboutReserve(for: [maya], in: index, slices: slices, budget: AskContextBuilder.openAIBudget) == slices.about)

        // On device the slice alone would swallow most of the budget, so the share cap is what
        // leaves room for an entry.
        let onDevice = AskRetrieval.slices(budget: 1_200, provider: .onDevice)
        let reserve = AskRetrieval.aboutReserve(for: [maya], in: index, slices: onDevice, budget: 1_200)
        #expect(reserve <= 600)
    }

    @Test func namingSomeoneWithNothingWrittenAboutThemCostsNothing() {
        let bare = AskIndex.Entity(id: maya, name: "Maya", kindRaw: "person", aboutCharacters: 0)
        let index = AskIndex.build(from: [input("a", blockCharacters: 100)], entities: [bare])
        let slices = AskRetrieval.slices(budget: AskContextBuilder.openAIBudget, provider: .openAI)
        #expect(AskRetrieval.aboutReserve(for: [maya], in: index, slices: slices, budget: AskContextBuilder.openAIBudget) == 2)
    }

    // MARK: - The estimate against what is really rendered

    @Test func theEstimateMatchesWhatTheRendererProduces() {
        // The cost line's only job is to be honest about what goes out, so the plan's arithmetic has
        // to agree with the renderer rather than being checked against the budget alone.
        let texts = (0..<6).map { index in String(repeating: "kayak paddle river ", count: 20 + index * 5) }
        let inputs = texts.enumerated().map { offset, text in
            AskIndex.DocumentInput(
                id: id(for: "entry\(offset)"),
                date: now.addingTimeInterval(-Double(offset) * 86_400),
                text: text,
                blockCharacters: AskContextBuilder.blockCharacterEstimate(title: "", text: text)
            )
        }
        let index = AskIndex.build(from: inputs)
        let result = plan("kayak", in: index)

        let selection = AskSources.Selection(
            entries: result.entryIDs.enumerated().compactMap { offset, id in
                guard let document = index.document(withID: id) else { return nil }
                return AskContextBuilder.EntryInput(id: id, date: document.date, title: "", text: texts[offset])
            }
        )
        let rendered = AskContextBuilder.render(plan: result, selection: selection, budget: AskContextBuilder.openAIBudget)

        #expect(rendered.entryIDs.count == result.entryIDs.count, "the plan promised entries the renderer dropped")
        // An upper bound, never an under-promise: sanitizing only removes characters.
        #expect(rendered.characters <= result.estimatedCharacters)
        #expect(Double(rendered.characters) > Double(result.estimatedCharacters) * 0.9)
    }

    // MARK: - Nothing to send

    // A7's tier 4, which the rewrite dropped by accident. A question sharing no word with the
    // journal used to send the newest entries; "nothing to go on" offers no Retry, so losing it
    // turned an ordinary question into a dead end.
    // A range that catches nothing is not a range the prompt may claim: the fallback sends the
    // newest entries in the journal, not the newest in that month.
    @Test func aRangeThatMatchesNothingIsNotClaimed() {
        let journal = index([input("a", daysAgo: 300, blockCharacters: 100)])
        let result = plan("What did I do last week?", in: journal)
        #expect(result.matchedNothing)
        #expect(result.appliedRange == nil)
        #expect(result.rangeWasInherited == false)
    }

    @Test func aQuestionThatMatchesNothingFallsBackToTheNewestEntries() {
        let inputs = (0..<8).map { input("entry\($0)", text: "the deadline moved", daysAgo: $0, blockCharacters: 100) }
        let result = plan("ayahuasca", in: index(inputs))

        #expect(result.rankedEntryIDs.count == AskRetrieval.recencyFallbackCount)
        #expect(result.rankedEntryIDs.first == id(for: "entry0"), "newest first")
        #expect(result.matchedNothing)
        // Nothing was cut from a match set, so there is nothing for the prompt to own up to.
        #expect(result.wasCut == false)
    }

    @Test func anEmptyJournalPlansNothing() {
        let result = plan("deadline", in: AskIndex.empty)
        #expect(result.isEmpty)
        #expect(result.matchedCount == 0)
    }

    @Test func aZeroBudgetPlansNoEntries() {
        let result = plan("deadline", in: index([input("a", blockCharacters: 100)]), budget: 0)
        #expect(result.rankedEntryIDs.isEmpty)
        #expect(result.estimatedCharacters == 0)
    }

    // MARK: - An entry the conversation is about

    private func focus(_ name: String, characters: Int, isSendable: Bool = true) -> AskIndex.DocumentInput {
        let text = String(repeating: "Quiet morning by the water. ", count: characters / 28 + 1).prefix(characters)
        return AskIndex.DocumentInput(
            id: id(for: name),
            date: now.addingTimeInterval(-86_400 * 40),
            text: String(text),
            isSendable: isSendable,
            blockCharacters: AskContextBuilder.blockCharacterEstimate(title: "", text: String(text)),
            textCharacters: text.count
        )
    }

    private func plan(_ question: String, focusing focusID: UUID, in index: AskIndex) -> AskRetrieval.Plan {
        AskRetrieval.plan(
            query: query(question, in: index),
            index: index,
            budget: AskContextBuilder.openAIBudget,
            provider: .openAI,
            focusEntryID: focusID,
            calendar: calendar
        )
    }

    @Test func theFocusGoesFirstAndWholePastTheUsualCap() {
        let index = index([focus("focus", characters: 5_000), input("a")])
        let result = plan("deadline", focusing: id(for: "focus"), in: index)

        #expect(result.focusEntryID == id(for: "focus"))
        #expect(result.focusTextLimit == 5_000, "all of it, not maxEntryCharacters")
        #expect(result.entryIDs.first == id(for: "focus"))
        // The rest of the journal is still searched.
        #expect(result.rankedEntryIDs == [id(for: "a")])
    }

    @Test func aVeryLongFocusIsCappedOnOpenAI() {
        let index = index([focus("focus", characters: 50_000)])
        let result = plan("water", focusing: id(for: "focus"), in: index)

        #expect(result.focusTextLimit > 23_000)
        #expect(result.focusTextLimit <= AskRetrieval.maxFocusCharactersOpenAI)
    }

    @Test func theFocusIsNeverRankedOrDigestedAgain() {
        let index = index([focus("focus", characters: 500), input("a", text: "Quiet morning by the water.")])
        let result = plan("quiet morning water", focusing: id(for: "focus"), in: index)

        #expect(result.entryIDs.filter { $0 == id(for: "focus") }.count == 1)
        #expect(!result.rankedEntryIDs.contains(id(for: "focus")))
        #expect(!result.digestEntryIDs.contains(id(for: "focus")))
        #expect(result.rankedEntryIDs == [id(for: "a")])
    }

    // "What do you make of this?" shares no word with the journal, and is about the entry, not a
    // reason to send the newest five and say nothing matched.
    @Test func aQuestionMatchingNothingKeepsTheFocusAndSkipsTheRecencyFallback() {
        let index = index([focus("focus", characters: 500), input("a"), input("b")])
        let result = plan("zebra", focusing: id(for: "focus"), in: index)

        #expect(!result.matchedNothing)
        #expect(result.entryIDs == [id(for: "focus")])
    }

    @Test func aFocusThatMayNotBeSentIsDropped() {
        let index = index([focus("focus", characters: 500, isSendable: false), input("a")])
        let result = plan("deadline", focusing: id(for: "focus"), in: index)

        #expect(result.focusEntryID == nil)
        #expect(!result.entryIDs.contains(id(for: "focus")))
    }
}
