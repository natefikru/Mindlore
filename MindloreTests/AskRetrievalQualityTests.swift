import Foundation
import Testing
@testable import Mindlore

// The measurement the phase exists to leave behind.
//
// A fixed corpus, a fixed set of questions, and the entry each question is actually about, written
// from the entry text before retrieval was run once. It reports recall@5 per question, so a
// regression names the question it broke, and it records the questions lexical retrieval cannot
// answer instead of pretending they don't exist. That is the number the owner decides about
// embeddings with: guessing is what the research warned against.
//
// Follow-ups are scored against the index alone, with the continuity slice out of the picture. With
// continuity in, a follow-up would score well because the last answer's entries come back regardless
// of whether retrieval found them, and the suite would be marking its own homework.
struct AskRetrievalQualityTests {
    // Monday 14 September 2026, 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_394_400)

    private struct Doc {
        let key: String
        let daysAgo: Int
        var title = ""
        let text: String
        var people: [String] = []
        var tags: [String] = []
        var area: String?
        var mood: String?
    }

    private struct Scenario {
        let question: String
        var previous: [String] = []
        let expected: [String]
        var note = ""
    }

    // Twenty-five entries over ten months: people who recur, threads that resolve, and the ordinary
    // days in between that a real journal is mostly made of.
    private var corpus: [Doc] {
        [
            Doc(key: "maya-move", daysAgo: 210, text: "Maya told me she is moving to Denver in the spring. She has been talking about leaving for a year but this time she has a lease.", people: ["Maya"], tags: ["moving"], area: "Friends"),
            Doc(key: "maya-quiet", daysAgo: 180, text: "Coffee with Maya. She was quiet the whole time and left early. Something is off and she would not say what.", people: ["Maya"], area: "Friends", mood: "worried"),
            Doc(key: "maya-call", daysAgo: 30, text: "Maya called from Denver. She sounded better than she has in months.", people: ["Maya"], area: "Friends"),
            Doc(key: "denver-visit", daysAgo: 20, text: "Flew out to see Maya in Denver. The altitude wrecked me for two days.", people: ["Maya", "Denver"], area: "Friends"),
            Doc(key: "fence", daysAgo: 34, text: "Rebuilt the fence all morning. Maya came by at lunch and we ate on the step.", people: ["Maya"], area: "Home"),
            Doc(key: "river-sarah", daysAgo: 120, text: "Walked the river loop with Sarah. We talked about her thesis the whole way.", people: ["Sarah"], tags: ["walking"], area: "Friends"),
            Doc(key: "kayak", daysAgo: 118, text: "Sarah brought the kayak over and we never got it in the water. Spent the afternoon patching the hull instead.", people: ["Sarah"], tags: ["kayak"], area: "Play"),
            Doc(key: "birthday", daysAgo: 2, text: "Sarah's birthday dinner. Eleven of us at the long table and nobody looked at a phone.", people: ["Sarah"], area: "Friends"),
            Doc(key: "burnout", daysAgo: 150, text: "Third week of running on empty. I got through the standup and then sat in the car for twenty minutes before I could drive home.", tags: ["sleep"], area: "Work", mood: "tired"),
            Doc(key: "sleep", daysAgo: 149, text: "Slept eleven hours and woke up just as tired.", tags: ["sleep"], area: "Health", mood: "tired"),
            Doc(key: "deadline-moved", daysAgo: 100, text: "The deadline moved again. Third time this quarter.", tags: ["deadline"], area: "Work"),
            Doc(key: "deadline-shipped", daysAgo: 60, text: "We shipped. The deadline held and nobody had to work the weekend.", tags: ["deadline"], area: "Work"),
            Doc(key: "landlord", daysAgo: 45, text: "Called the landlord about the lease. He says he will send the renewal in April.", tags: ["lease"], area: "Home"),
            Doc(key: "dentist", daysAgo: 44, text: "Dentist. Two fillings and a lecture about flossing.", area: "Health"),
            Doc(key: "climbing", daysAgo: 90, text: "First time back at the climbing gym since the shoulder thing. Managed three routes.", tags: ["climbing"], area: "Play"),
            Doc(key: "shoulder", daysAgo: 200, text: "Shoulder went again reaching for a hold. Same spot as last year.", tags: ["climbing", "injury"], area: "Health"),
            Doc(key: "mum-call", daysAgo: 75, text: "Long call with Mum. She is worried about Dad's test results.", people: ["Mum", "Dad"], area: "Family", mood: "worried"),
            Doc(key: "dad-results", daysAgo: 70, text: "Dad's results came back clear. Relief like a physical thing.", people: ["Dad"], area: "Family"),
            Doc(key: "money", daysAgo: 55, text: "Ran the numbers. If I keep this up I can clear the card by August.", tags: ["debt"], area: "Money"),
            Doc(key: "raise", daysAgo: 40, text: "Asked for the raise. He said he would take it to the committee, which is what he said last time.", tags: ["money"], area: "Work"),
            Doc(key: "garden", daysAgo: 35, text: "Put the tomatoes in. Too late in the season but the soil was finally dry.", tags: ["garden"], area: "Home"),
            Doc(key: "book", daysAgo: 25, text: "Finished the Rachel Cusk. Read the last forty pages standing up in the kitchen.", tags: ["reading"], area: "Play"),
            Doc(key: "therapy", daysAgo: 15, text: "First therapy session in two years. Mostly talked about work.", tags: ["therapy"], area: "Mind"),
            Doc(key: "therapy-two", daysAgo: 8, text: "Second session. She asked what I would do if the job vanished tomorrow and I had no answer.", tags: ["therapy"], area: "Mind"),
            Doc(key: "running", daysAgo: 5, text: "Ran the loop in thirty-one minutes. Slowest in months but I went.", tags: ["running"], area: "Health"),
        ]
    }

    // Questions a person would actually type, with the entries that answer them.
    private var fair: [Scenario] {
        [
            Scenario(question: "What's going on with Maya?", expected: ["maya-quiet", "maya-move", "maya-call"]),
            // The flagship. Every word of this follow-up is a stop word except "started", which
            // appears in no entry at all. Today it retrieves whatever else used that word and loses
            // her; the carryforward is what keeps it about Maya.
            Scenario(question: "Why do you think that started?", previous: ["What's going on with Maya?"], expected: ["maya-quiet", "maya-move"], note: "flagship follow-up"),
            Scenario(question: "Why?", previous: ["What's going on with Maya?"], expected: ["maya-quiet", "maya-move"], note: "nothing but stop words"),
            Scenario(question: "When did Maya move to Denver?", expected: ["maya-move"]),
            Scenario(question: "What happened with the deadline?", expected: ["deadline-moved", "deadline-shipped"]),
            Scenario(question: "Did I ever get the kayak in the water?", expected: ["kayak"]),
            Scenario(question: "What did the landlord say about the lease?", expected: ["landlord"]),
            Scenario(question: "How is Dad?", expected: ["dad-results", "mum-call"]),
            Scenario(question: "What did I do about the credit card?", expected: ["money"]),
            Scenario(question: "Did I ask for a raise?", expected: ["raise"]),
            Scenario(question: "How's my shoulder?", expected: ["shoulder", "climbing"]),
            Scenario(question: "What have I written about therapy?", expected: ["therapy", "therapy-two"]),
            Scenario(question: "What did I put in the garden?", expected: ["garden"]),
            Scenario(question: "Did I go running?", expected: ["running"]),
            Scenario(question: "What did Sarah and I do together?", expected: ["river-sarah", "kayak", "birthday"]),
            // Was a known miss until AskIndex started indexing lemmas: "run" against "ran" is an
            // irregular verb, so a stemmer would not have moved it and a lexicon did. Promoted
            // rather than quietly enjoyed, which is what the miss assertion asks for.
            Scenario(question: "How was the run?", expected: ["running"], note: "lemma, was a known miss"),
        ]
    }

    // What lexical retrieval cannot do. Recorded rather than hidden: these are the whole argument
    // for embeddings, and they are worth more to the owner as two measured classes than as a claim.
    private var knownMisses: [Scenario] {
        [
            // The vocabulary gap. The journal says "running on empty"; nobody asks it that way.
            // Worse, "spring" pulls in the entry about Maya moving in the spring instead.
            Scenario(question: "Was I burnt out in the spring?", expected: ["burnout"], note: "synonym"),
        ]
    }

    // MARK: - Running

    private func index(_ docs: [Doc]) -> AskIndex {
        var entities: [AskIndex.Entity] = []
        var idsByName: [String: UUID] = [:]
        for name in docs.flatMap(\.people) where idsByName[name] == nil {
            let id = UUID()
            idsByName[name] = id
            entities.append(AskIndex.Entity(id: id, name: name, kindRaw: "person"))
        }
        let inputs = docs.map { doc in
            AskIndex.DocumentInput(
                id: id(for: doc.key),
                date: now.addingTimeInterval(-Double(doc.daysAgo) * 86_400),
                title: doc.title,
                text: doc.text,
                entityIDs: doc.people.compactMap { idsByName[$0] },
                entityNames: doc.people,
                tags: doc.tags,
                areas: [doc.area].compactMap { $0 },
                mood: doc.mood,
                isSendable: true,
                blockCharacters: AskContextBuilder.blockCharacterEstimate(title: doc.title, text: doc.text)
            )
        }
        return AskIndex.build(from: inputs, entities: entities)
    }

    private func id(for key: String) -> UUID {
        var bytes = Array(key.utf8.prefix(16))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16 - bytes.count))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    // Retrieval only. No continuity slice, so what is measured is whether the query found the
    // entries rather than whether the last turn happened to be holding them.
    private func topKeys(_ scenario: Scenario, in index: AskIndex, k: Int = 5) -> [String] {
        let query = AskRetrievalQuery.build(
            question: scenario.question,
            previousQuestions: scenario.previous,
            citedEntryIDs: [],
            index: index,
            now: now,
            calendar: calendar
        )
        let keysByID = Dictionary(corpus.map { (id(for: $0.key), $0.key) }, uniquingKeysWith: { first, _ in first })
        return index.search(query.indexQuery).prefix(k).compactMap { keysByID[index.documents[Int($0.document)].id] }
    }

    private func recall(_ scenario: Scenario, in index: AskIndex) -> Double {
        let found = Set(topKeys(scenario, in: index))
        let hits = scenario.expected.count { found.contains($0) }
        return Double(hits) / Double(scenario.expected.count)
    }

    // MARK: - The measurement

    @Test func recallAtFiveOverTheFixedQuestionSet() {
        let index = index(corpus)
        var report = ["", "recall@5 over \(corpus.count) entries:"]
        var total = 0.0

        for scenario in fair {
            let score = recall(scenario, in: index)
            total += score
            let note = scenario.note.isEmpty ? "" : "  (\(scenario.note))"
            report.append(String(format: "  %.2f  %@%@", score, scenario.question, note))
            if score < 1 {
                report.append("        got: \(topKeys(scenario, in: index).joined(separator: ", "))")
                report.append("        wanted: \(scenario.expected.joined(separator: ", "))")
            }
        }

        let mean = total / Double(fair.count)
        report.append(String(format: "  mean %.3f over %d questions", mean, fair.count))
        report.append("")
        print(report.joined(separator: "\n"))

        // Per question, not on the mean. A floor of 0.93 across fifteen questions let one of them
        // regress from 1.00 to 0.00 and still pass, which is the opposite of what the floor was for:
        // a regression has to name the question it broke.
        for scenario in fair {
            let score = recall(scenario, in: index)
            #expect(score == 1, "\"\(scenario.question)\" fell to \(score); the report above says what it got")
        }
        #expect(mean == 1)
    }

    // Recall over a corpus where every answer owns a rare keyword mostly measures that the tokenizer
    // runs. These are the cases where the ranking itself has to be right: the recency floor, the
    // body and context split, and contextFactor could each be broken without moving the number
    // above, and each of these goes red.
    @Test func theRankingItselfAndNotJustTheTokenizer() throws {
        let index = index(corpus)

        // Two entries about the deadline, forty days apart. The older one leads because it is
        // shorter and the word is a bigger share of it, which is length normalization outweighing a
        // forty-day recency gap, and the newer one is still right behind it. Counting keyword hits,
        // as the old tier 2 did, could not tell these apart at all.
        let deadline = topKeys(Scenario(question: "What happened with the deadline?", expected: []), in: index)
        #expect(deadline.first == "deadline-moved")
        #expect(deadline.contains("deadline-shipped"))

        // An entry that writes her name beats one merely linked to her.
        let maya = topKeys(Scenario(question: "What's going on with Maya?", expected: []), in: index)
        #expect(maya.first == "maya-call")
        #expect(maya.contains("fence"), "and the one that only mentions her in passing still appears")

        // A question whose word appears in no entry body, answered entirely through tags.
        let therapy = topKeys(Scenario(question: "therapy", expected: []), in: index)
        #expect(Set(therapy.prefix(2)) == ["therapy", "therapy-two"])

        // Two entries name the shoulder once each at almost the same length, so this is the near
        // tie recency exists to break: the ninety-day-old one leads the two-hundred-day-old one. The
        // floor is what keeps the older one in the list a place behind rather than burying it, and
        // at a floor of 0.5 it would not be there.
        let shoulder = topKeys(Scenario(question: "How's my shoulder?", expected: []), in: index)
        #expect(shoulder.first == "climbing")
        #expect(shoulder.contains("shoulder"))
    }

    // The one that proves the phase. Kept separate from the mean so it can never be averaged away by
    // fourteen easy questions.
    @Test func aFollowUpThatNamesNobodyStillFindsTheSubject() {
        let index = index(corpus)
        let followUp = Scenario(question: "Why do you think that started?", previous: ["What's going on with Maya?"], expected: ["maya-quiet", "maya-move"])
        #expect(recall(followUp, in: index) == 1)

        // And with no carryforward at all, which is today's behaviour, it finds neither.
        let alone = Scenario(question: "Why do you think that started?", expected: ["maya-quiet", "maya-move"])
        #expect(recall(alone, in: index) < 1, "if this passes, the corpus stopped being able to show the bug")
    }

    @Test func theQuestionsLexicalRetrievalCannotAnswer() {
        let index = index(corpus)
        var report = ["", "known misses:"]
        for scenario in knownMisses {
            let score = recall(scenario, in: index)
            report.append(String(format: "  %.2f  %@  (%@)", score, scenario.question, scenario.note))
            report.append("        got: \(topKeys(scenario, in: index).joined(separator: ", "))")
            // Asserted as misses on purpose. If one starts passing, the honest move is to promote it
            // into the fair set, not to quietly enjoy it.
            #expect(score < 1, "\"\(scenario.question)\" now works; move it into the fair set")
        }
        report.append("")
        print(report.joined(separator: "\n"))
    }
}
