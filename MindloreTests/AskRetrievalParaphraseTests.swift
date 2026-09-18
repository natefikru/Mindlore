import Foundation
import Testing
@testable import Mindlore

// How often lexical retrieval finds the right entry when the question does not share the entry's
// words. This is the number the embeddings decision gets made with.
//
// `AskRetrievalQualityTests` is the regression guard: fifteen questions that must stay at 1.00, and
// two known misses. It is deliberately not this. Two misses is an anecdote, and recall@5 over its
// twenty-five entries is generous, because five is a fifth of the corpus. This file exists to turn
// the anecdote into a rate: a corpus big enough that being in the top five means something, and
// enough paraphrases, sorted by why they are hard, to say which kinds of question fail and how
// often.
//
// Every entry was written before any question was, and every expected answer was chosen by reading
// the entries rather than by running retrieval. Distractors are deliberate: entries that share a
// question's words without answering it, because a corpus where each answer owns a rare keyword
// measures the tokenizer rather than the ranking.
//
// Nothing here is asserted at 1.00. These are the questions lexical retrieval is expected to fail.
// What is asserted is that the gap between this set and the fair set is still real, so that if
// stemming or embeddings close it, somebody has to come back and say so.
struct AskRetrievalParaphraseTests {
    // Monday 14 September 2026, 14:00 UTC, the same instant the quality suite uses.
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

    private enum Kind: String, CaseIterable {
        // The journal's word and the question's word mean the same thing and share no letters.
        case synonym = "synonym"
        // Same root, different form. "Ran" against "run", "flew" against "flying".
        case morphology = "morphology"
        // The question describes the event without using any word the entry uses.
        case description = "indirect description"
        // The question asks for a category the entry is an instance of.
        case category = "category"
        // The entry shows a feeling without naming it; the question names it.
        case feeling = "feeling"
    }

    private struct Scenario {
        let kind: Kind
        let question: String
        let expected: [String]
        // What makes it hard, and what is expected to be retrieved instead.
        var trap = ""
    }

    // MARK: - The journal

    // Fifty-six entries across about fourteen months. Roughly a third are the ordinary days a real
    // journal is mostly made of, and several exist only to be tempting wrong answers.
    private var corpus: [Doc] {
        [
            // Work, and the slow shape of leaving it.
            Doc(key: "standup-empty", daysAgo: 400, text: "Third week of running on empty. Got through the standup and then sat in the car for twenty minutes before I could drive home.", tags: ["sleep"], area: "Work", mood: "tired"),
            Doc(key: "sleep-eleven", daysAgo: 399, text: "Slept eleven hours and woke up just as tired.", tags: ["sleep"], area: "Health", mood: "tired"),
            Doc(key: "deadline-moved", daysAgo: 360, text: "The deadline moved again. Third time this quarter.", tags: ["deadline"], area: "Work"),
            Doc(key: "deadline-shipped", daysAgo: 300, text: "We shipped. The deadline held and nobody had to work the weekend.", tags: ["deadline"], area: "Work"),
            Doc(key: "raise-asked", daysAgo: 250, text: "Asked for the raise. He said he would take it to the committee, which is what he said last time.", tags: ["money"], area: "Work"),
            Doc(key: "raise-nothing", daysAgo: 180, text: "Still nothing from the committee. I have stopped bringing it up.", tags: ["money"], area: "Work"),
            Doc(key: "row-with-boss", daysAgo: 150, text: "It got heated with Tom in the review. I said things I had been holding for a year and he went very quiet.", people: ["Tom"], area: "Work", mood: "angry"),
            Doc(key: "apology", daysAgo: 149, text: "Tom came by my desk and we sorted it out. Neither of us said sorry exactly but it is fine now.", people: ["Tom"], area: "Work"),
            Doc(key: "notice-thought", daysAgo: 120, text: "Drafted the resignation letter on the train and deleted it before my stop.", area: "Work"),
            Doc(key: "job-ad", daysAgo: 95, text: "Sent the application. First one in four years and it took me the whole evening.", tags: ["job hunt"], area: "Work"),
            Doc(key: "interview", daysAgo: 70, text: "They asked where I see myself and I gave the answer everyone gives. Walked out knowing I do not want it.", tags: ["job hunt"], area: "Work"),
            Doc(key: "stayed", daysAgo: 60, text: "Turned it down. Told myself it was the commute but it was not the commute.", tags: ["job hunt"], area: "Work"),

            // Maya, and Denver.
            Doc(key: "maya-move", daysAgo: 340, text: "Maya told me she is moving to Denver in the spring. She has been talking about leaving for a year but this time she has a lease.", people: ["Maya"], tags: ["moving"], area: "Friends"),
            Doc(key: "maya-quiet", daysAgo: 310, text: "Coffee with Maya. She was quiet the whole time and left early. Something is off and she would not say what.", people: ["Maya"], area: "Friends", mood: "worried"),
            Doc(key: "maya-goodbye", daysAgo: 240, text: "Helped Maya load the van. We stood on the pavement afterwards not knowing how to end it.", people: ["Maya"], tags: ["moving"], area: "Friends"),
            Doc(key: "maya-call", daysAgo: 90, text: "Maya called from Denver. She sounded better than she has in months.", people: ["Maya"], area: "Friends"),
            Doc(key: "denver-flew", daysAgo: 50, text: "Flew out to see Maya. The altitude wrecked me for two days and I slept through the first afternoon.", people: ["Maya"], area: "Friends"),
            Doc(key: "fence", daysAgo: 330, text: "Rebuilt the fence all morning. Maya came by at lunch and we ate on the step.", people: ["Maya"], area: "Home"),

            // Sarah.
            Doc(key: "river-sarah", daysAgo: 320, text: "Walked the river loop with Sarah. We talked about her thesis the whole way.", people: ["Sarah"], tags: ["walking"], area: "Friends"),
            Doc(key: "kayak", daysAgo: 318, text: "Sarah brought the kayak over and we never got it in the water. Spent the afternoon patching the hull instead.", people: ["Sarah"], tags: ["kayak"], area: "Play"),
            Doc(key: "thesis-done", daysAgo: 200, text: "Sarah handed in. Four years and she described it as putting down a bag.", people: ["Sarah"], area: "Friends"),
            Doc(key: "birthday", daysAgo: 12, text: "Sarah's birthday dinner. Eleven of us at the long table and nobody looked at a phone.", people: ["Sarah"], area: "Friends"),

            // Family.
            Doc(key: "mum-call", daysAgo: 275, text: "Long call with Mum. She is worried about Dad's test results.", people: ["Mum", "Dad"], area: "Family", mood: "worried"),
            Doc(key: "dad-results", daysAgo: 270, text: "Dad's results came back clear. Relief like a physical thing.", people: ["Dad"], area: "Family"),
            Doc(key: "dad-garden", daysAgo: 190, text: "Spent Saturday with Dad. He wanted the apple tree down and I talked him out of it.", people: ["Dad"], area: "Family"),
            Doc(key: "mum-birthday", daysAgo: 100, text: "Mum turned seventy. She made her own cake, which tells you everything.", people: ["Mum"], area: "Family"),
            Doc(key: "nephew", daysAgo: 45, text: "Took Leo to the pool. He went off the high board on the fourth try and then would not stop.", people: ["Leo"], area: "Family"),

            // Body.
            Doc(key: "shoulder-went", daysAgo: 380, text: "Shoulder went again reaching for a hold. Same spot as last year.", tags: ["climbing", "injury"], area: "Health"),
            Doc(key: "physio", daysAgo: 350, text: "Physio says six weeks and no overhead work. Six weeks.", tags: ["injury"], area: "Health"),
            Doc(key: "climbing-back", daysAgo: 280, text: "First time back at the climbing gym since the shoulder thing. Managed three routes.", tags: ["climbing"], area: "Play"),
            Doc(key: "ran-loop", daysAgo: 30, text: "Ran the loop in thirty-one minutes. Slowest in months but I went.", tags: ["running"], area: "Health"),
            Doc(key: "ran-again", daysAgo: 16, text: "Ran again before work. It is getting easier which is the whole point.", tags: ["running"], area: "Health"),
            Doc(key: "swim", daysAgo: 130, text: "Swam a mile for the first time since school. Arms like string afterwards.", tags: ["swimming"], area: "Health"),
            Doc(key: "dentist", daysAgo: 220, text: "Dentist. Two fillings and a lecture about flossing.", area: "Health"),
            Doc(key: "flu", daysAgo: 160, text: "Three days flat on my back. Watched an entire series and remember none of it.", area: "Health"),

            // Money and the flat.
            Doc(key: "card", daysAgo: 265, text: "Ran the numbers. If I keep this up I can clear the card by August.", tags: ["debt"], area: "Money"),
            Doc(key: "card-cleared", daysAgo: 110, text: "Paid the last of it. Sat looking at a zero for a while.", tags: ["debt"], area: "Money"),
            Doc(key: "landlord", daysAgo: 230, text: "Called the landlord about the lease. He says he will send the renewal in April.", tags: ["lease"], area: "Home"),
            Doc(key: "rent-up", daysAgo: 140, text: "Renewal came. Ninety more a month and no mention of the damp.", tags: ["lease"], area: "Home"),
            Doc(key: "boiler", daysAgo: 175, text: "The boiler gave out. Two days of cold showers before anyone came to look at it.", area: "Home"),
            Doc(key: "garden", daysAgo: 210, text: "Put the tomatoes in. Too late in the season but the soil was finally dry.", tags: ["garden"], area: "Home"),
            Doc(key: "tomatoes", daysAgo: 115, text: "Nine tomatoes off four plants. Not a triumph but they were mine.", tags: ["garden"], area: "Home"),

            // Mind.
            Doc(key: "therapy-one", daysAgo: 85, text: "First therapy session in two years. Mostly talked about work.", tags: ["therapy"], area: "Mind"),
            Doc(key: "therapy-two", daysAgo: 78, text: "Second session. She asked what I would do if the job vanished tomorrow and I had no answer.", tags: ["therapy"], area: "Mind"),
            Doc(key: "therapy-three", daysAgo: 40, text: "She used the word avoidance and I have been chewing on it since.", tags: ["therapy"], area: "Mind"),

            // Ordinary days, and the distractors.
            Doc(key: "book-cusk", daysAgo: 105, text: "Finished the Rachel Cusk. Read the last forty pages standing up in the kitchen.", tags: ["reading"], area: "Play"),
            Doc(key: "book-two", daysAgo: 55, text: "Started the Mantel. Six hundred pages and I am in no hurry.", tags: ["reading"], area: "Play"),
            // A spring entry with no exhaustion in it, to tempt "burnt out in the spring".
            Doc(key: "spring-walk", daysAgo: 170, text: "First proper spring day. Walked into town with no coat and felt about nineteen.", area: "Play", mood: "content"),
            // A "run" that is not running, to tempt a morphology question.
            Doc(key: "run-errands", daysAgo: 65, text: "Ran every errand I had been putting off. The post office queue alone took an hour.", area: "Home"),
            // A "cold" that is weather, to tempt a health question.
            Doc(key: "cold-snap", daysAgo: 125, text: "Cold snap. Scraped the car twice before eight.", area: "Home"),
            Doc(key: "pub-quiz", daysAgo: 88, text: "Pub quiz. Came fourth and argued about the capital of Australia for ten minutes.", area: "Friends"),
            Doc(key: "concert", daysAgo: 35, text: "Saw them at the Barrowlands. Ears ringing on the bus home and worth it.", area: "Play"),
            Doc(key: "wedding", daysAgo: 155, text: "Priya's wedding. Danced badly and stayed later than I meant to.", people: ["Priya"], area: "Friends"),
            Doc(key: "car-sold", daysAgo: 75, text: "Sold the car to a man who barely looked at it. Feels strange not having it outside.", area: "Money"),
            Doc(key: "haircut", daysAgo: 20, text: "Cut it all off. Regret is at about thirty percent.", area: "Play"),
            Doc(key: "quiet-sunday", daysAgo: 7, text: "Did not leave the flat. Read, cooked, went to bed early. No notes.", area: "Play", mood: "content"),
            Doc(key: "rain", daysAgo: 3, text: "Rained all day. Watched it off the back step with tea and did not mind.", area: "Play", mood: "calm"),
        ]
    }

    // MARK: - The questions

    // Written after the entries, by reading them. Each one is a way a person would really ask, and
    // each one shares little or nothing with the words the entry uses.
    private var paraphrases: [Scenario] {
        [
            // Synonym.
            Scenario(kind: .synonym, question: "Was I burnt out at work?", expected: ["standup-empty"], trap: "journal says \"running on empty\"; \"work\" is in a dozen entries"),
            Scenario(kind: .synonym, question: "Did I have a row with anyone?", expected: ["row-with-boss"], trap: "journal says \"it got heated\""),
            Scenario(kind: .synonym, question: "When did I quit my job?", expected: ["notice-thought", "stayed"], trap: "journal says \"resignation letter\" and never \"quit\""),
            Scenario(kind: .synonym, question: "Did I get a pay rise?", expected: ["raise-asked", "raise-nothing"], trap: "\"pay rise\" against \"raise\""),
            Scenario(kind: .synonym, question: "What did the doctor say about my arm?", expected: ["physio", "shoulder-went"], trap: "\"doctor\" against \"physio\", \"arm\" against \"shoulder\""),
            Scenario(kind: .synonym, question: "Did I ever pay off my debt?", expected: ["card-cleared"], trap: "journal says \"paid the last of it\" and \"a zero\""),

            // Morphology.
            Scenario(kind: .morphology, question: "How was the run?", expected: ["ran-loop", "ran-again"], trap: "\"run\" against \"ran\"; the errands entry also says \"ran\""),
            Scenario(kind: .morphology, question: "When did I fly to Denver?", expected: ["denver-flew"], trap: "\"fly\" against \"flew\""),
            Scenario(kind: .morphology, question: "What have I been reading?", expected: ["book-cusk", "book-two"], trap: "\"reading\" is the tag, \"read\" is the word"),
            Scenario(kind: .morphology, question: "How is my climbing going?", expected: ["climbing-back", "shoulder-went"], trap: "should be easy; here as the control for the class"),

            // Indirect description.
            Scenario(kind: .description, question: "When did I last see Maya in person before she left?", expected: ["maya-goodbye"], trap: "the entry never says \"last\", \"see\", or \"left\""),
            Scenario(kind: .description, question: "Was there a health scare in the family?", expected: ["mum-call", "dad-results"], trap: "journal says \"test results\" and \"came back clear\""),
            Scenario(kind: .description, question: "Did my rent go up?", expected: ["rent-up"], trap: "journal says \"ninety more a month\""),
            Scenario(kind: .description, question: "Have I been avoiding something?", expected: ["therapy-three"], trap: "the entry names avoidance; so does the errands one"),
            Scenario(kind: .description, question: "What happened with the flat's heating?", expected: ["boiler"], trap: "\"heating\" appears nowhere; the cold snap entry is the trap"),
            Scenario(kind: .description, question: "Did I ever grow anything?", expected: ["garden", "tomatoes"], trap: "\"grow\" appears in neither"),
            Scenario(kind: .description, question: "How did the interview go?", expected: ["interview"], trap: "the entry describes the interview without once saying the word"),

            // Category.
            Scenario(kind: .category, question: "What exercise have I done?", expected: ["ran-loop", "swim", "climbing-back"], trap: "no entry uses the word \"exercise\""),
            Scenario(kind: .category, question: "What have I done with my family?", expected: ["dad-garden", "mum-birthday", "nephew"], trap: "the area is Family but the word is not in the text"),
            Scenario(kind: .category, question: "Any big social events?", expected: ["wedding", "birthday", "concert"], trap: "\"social\" and \"event\" appear nowhere"),
            Scenario(kind: .category, question: "What did I spend money on?", expected: ["car-sold", "rent-up", "card"], trap: "the area is Money; \"spend\" is in none of them"),

            // Feeling.
            Scenario(kind: .feeling, question: "When was I happiest this year?", expected: ["dad-results", "spring-walk", "quiet-sunday"], trap: "no entry says happy"),
            Scenario(kind: .feeling, question: "What made me anxious?", expected: ["maya-quiet", "mum-call"], trap: "the mood is worried; the word anxious is nowhere"),
            Scenario(kind: .feeling, question: "Was I lonely after Maya went?", expected: ["maya-goodbye", "maya-call"], trap: "\"lonely\" appears nowhere in the journal"),
            Scenario(kind: .feeling, question: "Did anything make me proud?", expected: ["tomatoes", "card-cleared", "ran-again"], trap: "\"proud\" appears nowhere"),
        ]
    }

    // A control: the same corpus, questions that do share the entry's words. Without this the
    // paraphrase number means nothing, because a corpus can simply be hard.
    private var literal: [Scenario] {
        [
            Scenario(kind: .synonym, question: "What happened with the deadline?", expected: ["deadline-moved", "deadline-shipped"]),
            Scenario(kind: .synonym, question: "What did the landlord say about the lease?", expected: ["landlord"]),
            Scenario(kind: .synonym, question: "Did I ever get the kayak in the water?", expected: ["kayak"]),
            Scenario(kind: .synonym, question: "What have I written about therapy?", expected: ["therapy-one", "therapy-two", "therapy-three"]),
            Scenario(kind: .synonym, question: "Tell me about the boiler.", expected: ["boiler"]),
            Scenario(kind: .synonym, question: "What's going on with Maya?", expected: ["maya-call", "maya-quiet"]),
            Scenario(kind: .synonym, question: "When did Sarah hand in her thesis?", expected: ["thesis-done"]),
            Scenario(kind: .synonym, question: "What happened with my shoulder?", expected: ["shoulder-went", "climbing-back"]),
        ]
    }

    // MARK: - Plumbing

    private func buildIndex() -> AskIndex {
        var entities: [AskIndex.Entity] = []
        var idsByName: [String: UUID] = [:]
        for name in corpus.flatMap(\.people) where idsByName[name] == nil {
            let id = UUID()
            idsByName[name] = id
            entities.append(AskIndex.Entity(id: id, name: name, kindRaw: "person"))
        }
        let inputs = corpus.map { doc in
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

    private func topKeys(_ question: String, in index: AskIndex, k: Int) -> [String] {
        let query = AskRetrievalQuery.build(
            question: question,
            previousQuestions: [],
            citedEntryIDs: [],
            index: index,
            now: now,
            calendar: calendar
        )
        let keysByID = Dictionary(corpus.map { (id(for: $0.key), $0.key) }, uniquingKeysWith: { first, _ in first })
        return index.search(query.indexQuery).prefix(k).compactMap { keysByID[index.documents[Int($0.document)].id] }
    }

    private func recall(_ scenario: Scenario, in index: AskIndex, k: Int) -> Double {
        let found = Set(topKeys(scenario.question, in: index, k: k))
        let hits = scenario.expected.filter { found.contains($0) }.count
        return Double(hits) / Double(scenario.expected.count)
    }

    private func mean(_ scenarios: [Scenario], in index: AskIndex, k: Int) -> Double {
        guard !scenarios.isEmpty else { return 0 }
        return scenarios.reduce(0.0) { $0 + recall($1, in: index, k: k) } / Double(scenarios.count)
    }

    // MARK: - The measurement

    @Test func theParaphraseGap() {
        let index = buildIndex()
        var report = ["", "Paraphrase recall over \(corpus.count) entries", String(repeating: "=", count: 52)]

        let literalAt5 = mean(literal, in: index, k: 5)
        let literalAt10 = mean(literal, in: index, k: 10)
        report.append(String(format: "control (question shares the entry's words)  @5 %.2f  @10 %.2f  over %d", literalAt5, literalAt10, literal.count))
        for scenario in literal where recall(scenario, in: index, k: 5) < 1 {
            report.append(String(format: "   %.2f  %@", recall(scenario, in: index, k: 5), scenario.question))
            report.append("         wanted: \(scenario.expected.joined(separator: ", "))")
            report.append("         got:    \(topKeys(scenario.question, in: index, k: 5).joined(separator: ", "))")
        }
        report.append("")

        for kind in Kind.allCases {
            let group = paraphrases.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            report.append(String(format: "%@  @5 %.2f  @10 %.2f  over %d", kind.rawValue, mean(group, in: index, k: 5), mean(group, in: index, k: 10), group.count))
            for scenario in group {
                let at5 = recall(scenario, in: index, k: 5)
                report.append(String(format: "   %.2f  %@", at5, scenario.question))
                if at5 < 1 {
                    report.append("         wanted: \(scenario.expected.joined(separator: ", "))")
                    report.append("         got:    \(topKeys(scenario.question, in: index, k: 5).joined(separator: ", "))")
                    if !scenario.trap.isEmpty { report.append("         why:    \(scenario.trap)") }
                }
            }
            report.append("")
        }

        let paraphraseAt5 = mean(paraphrases, in: index, k: 5)
        let paraphraseAt10 = mean(paraphrases, in: index, k: 10)
        report.append(String(repeating: "-", count: 52))
        report.append(String(format: "all paraphrases  @5 %.2f  @10 %.2f  over %d", paraphraseAt5, paraphraseAt10, paraphrases.count))
        report.append(String(format: "the gap at 5: %.2f control against %.2f paraphrase", literalAt5, paraphraseAt5))
        let fullyMissed = paraphrases.filter { recall($0, in: index, k: 5) == 0 }
        report.append("questions that found nothing at all: \(fullyMissed.count) of \(paraphrases.count)")
        report.append("")
        print(report.joined(separator: "\n"))

        // The control has to hold, or the corpus is just hard and the comparison says nothing.
        #expect(literalAt5 >= 0.8, "the control fell to \(literalAt5); the corpus, not the paraphrasing, is the problem")
        // The finding. If this stops being true, lexical retrieval got better than expected and the
        // embeddings case needs rewriting rather than quietly winning.
        #expect(paraphraseAt5 < literalAt5, "paraphrases now score as well as literal questions; re-examine the case for embeddings")
    }
}
