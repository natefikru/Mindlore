import Foundation
import Testing
@testable import Mindlore

// Life or creative, measured on a fixed set whose answers were written before either model saw
// it. The error that matters is a life entry filed as creative: it loses its names and threads
// without anyone noticing. So the bar is zero of those, then as many real pieces caught as the
// engine can manage. Known misses are asserted as misses, so one starting to work has to be
// promoted rather than quietly enjoyed.
nonisolated enum CreativeCorpus {
    struct Item: Sendable {
        let name: String
        let text: String
        let creative: Bool
        // Laid out like verse, by CreativeSignals.looksLikeVerse.
        let verse: Bool
        // The on-device path can't catch it: prose, or verse under four lines.
        var onDeviceMiss = false
    }

    static let items: [Item] = [
        // Creative
        .init(name: "lyric", text: """
        Rosa drove to Memphis with the moon on the water
        headlights on the levee, nothing left to say
        oh Rosa, Rosa, the river keeps your name
        and I keep waiting for the morning anyway
        """, creative: true, verse: true),
        .init(name: "short poem", text: """
        the kettle knows
        before I do
        that the morning
        has already started
        without me
        """, creative: true, verse: true),
        .init(name: "punctuated poem", text: """
        I kept the letters in a shoebox.
        The rain got in anyway.
        What's left of your handwriting
        looks like weather now.
        """, creative: true, verse: true),
        .init(name: "chorus", text: """
        and we ran, we ran, we ran through the summer
        with nothing in our pockets but the sound of the sea
        and we ran, we ran, we ran through the summer
        you were never gonna wait for me
        """, creative: true, verse: true),
        .init(name: "stanzas", text: """
        The tide goes out the way you did,
        politely, taking everything.

        The gulls stay. They always stay.
        They have nowhere better to be.
        """, creative: true, verse: true),
        .init(name: "haiku", text: """
        wet streetlight
        one moth
        still trying
        """, creative: true, verse: false, onDeviceMiss: true),
        .init(name: "prose story", text: """
        The lighthouse keeper's daughter counted ships the way other children counted sheep. On \
        the night the lamp failed she walked the stairs alone, one hundred and twelve of them, and \
        lit it with her father's matches while the storm tried the door.
        """, creative: true, verse: false, onDeviceMiss: true),

        // Life
        .init(name: "about a song", text: """
        Worked on the Memphis song tonight after dinner. The second verse still doesn't land and I \
        need to call Dana about the studio time before Friday. Tired but it felt good to write.
        """, creative: false, verse: false),
        .init(name: "poetic prose", text: """
        Today felt like drowning in slow motion. Meetings stacked like wet cardboard and by four I \
        couldn't hear my own thoughts. Walked home the long way along the river and it helped a little.
        """, creative: false, verse: false),
        .init(name: "dream", text: """
        Dreamt I was back at my grandmother's house and the stairs kept going up past where the \
        roof should be. Woke up at 5 and couldn't get back to sleep. Called her later, she's fine.
        """, creative: false, verse: false),
        .init(name: "day with verse", text: """
        Long day at the shop. Priya came by at close and we talked about the fall festival booth.
        On the drive home this line wouldn't leave me alone:
        the river keeps your name
        and I keep waiting anyway
        Might turn it into something. Early night.
        """, creative: false, verse: false),
        .init(name: "grocery list", text: """
        milk
        eggs
        call mom
        pay rent
        batteries
        """, creative: false, verse: false),
        .init(name: "to-do bullets", text: """
        - email Priya about the deck
        - book the dentist for next week
        - renew the parking permit
        - finish reading chapter four
        """, creative: false, verse: false),
        .init(name: "gratitude list", text: """
        Grateful for:
        the sun on the balcony this morning
        Sam's text out of nowhere
        cold brew from the place on 5th
        finally finishing the draft
        """, creative: false, verse: true),
        .init(name: "standup notes", text: """
        Standup today:
        shipped the import fix to staging
        blocked on the API review again
        need Jordan's sign-off by Thursday
        """, creative: false, verse: true),
        .init(name: "coffee", text: """
        Coffee with Maya at Blue Door this morning. She's moving to Denver in March and I still \
        haven't decided whether to take the lead role Priya offered.
        """, creative: false, verse: false),
        .init(name: "one-liner", text: "Tired. Early night.", creative: false, verse: false),
        .init(name: "voice run-on", text: """
        okay so today was kind of a lot I got up late missed the bus had to call in and then my \
        brother called about dad's appointment so I'm driving him Thursday I guess
        """, creative: false, verse: false),
        .init(name: "quoting a poem", text: """
        Read Mary Oliver on the train. "Tell me, what is it you plan to do with your one wild and \
        precious life?" stuck with me all day. Didn't have an answer at lunch either.
        """, creative: false, verse: false),
    ]
}

struct CreativeSignalsTests {
    @Test func verseShapeMatchesTheLabels() {
        for item in CreativeCorpus.items {
            #expect(CreativeSignals.looksLikeVerse(item.text) == item.verse, "\(item.name)")
        }
    }

    @Test func onDeviceProseIsNeverCreativeWhateverTheModelSays() {
        let prose = CreativeCorpus.items.first { $0.name == "about a song" }!
        #expect(!CreativeSignals.decide(modelSaysCreative: true, text: prose.text, onDevice: true, focused: nil))
        #expect(CreativeSignals.decide(modelSaysCreative: true, text: prose.text, onDevice: false, focused: nil), "OpenAI is trusted")
    }

    @Test func onDeviceVerseNeedsTheFocusedYesAndAFailureMeansLife() {
        let lyric = CreativeCorpus.items.first { $0.name == "lyric" }!
        #expect(CreativeSignals.decide(modelSaysCreative: false, text: lyric.text, onDevice: true, focused: true))
        #expect(!CreativeSignals.decide(modelSaysCreative: true, text: lyric.text, onDevice: true, focused: false))
        #expect(!CreativeSignals.decide(modelSaysCreative: true, text: lyric.text, onDevice: true, focused: nil))
    }

    @Test func theFocusedAnswerParses() {
        #expect(CreativeSignals.parseFocused(#"{"kind":"poem or song lyrics"}"#) == true)
        #expect(CreativeSignals.parseFocused(#"{"kind":"list or notes"}"#) == false)
        #expect(CreativeSignals.parseFocused("nonsense") == nil)
    }
}

// Apple's model, the whole on-device path: the insights request for its verdict, then the
// focused question for verse-shaped text, then the rule.
struct CreativeOnDeviceQualityTests {
    @Test(.enabled(if: TestHost.canMeasureOnDeviceModel), .timeLimit(.minutes(8)))
    func theOnDevicePathNeverFilesLifeAsCreative() async throws {
        let generator = FoundationModelsTextGenerator()
        var wrongCreative: [String] = []
        var caught: [String] = []
        var missed: [String] = []
        for item in CreativeCorpus.items {
            var focused: Bool?
            if CreativeSignals.looksLikeVerse(item.text) {
                focused = (try? await generator.generate(CreativeSignals.focusedRequest(for: item.text))).flatMap { CreativeSignals.parseFocused($0.text) }
            }
            let creative = CreativeSignals.decide(modelSaysCreative: false, text: item.text, onDevice: true, focused: focused)
            if creative && !item.creative { wrongCreative.append(item.name) }
            if item.creative { creative ? caught.append(item.name) : missed.append(item.name) }
        }
        print("ON-DEVICE CREATIVE caught=\(caught) missed=\(missed) wrongCreative=\(wrongCreative)")
        #expect(wrongCreative.isEmpty, "life filed as creative: \(wrongCreative)")
        let expectedMisses = Set(CreativeCorpus.items.filter { $0.creative && $0.onDeviceMiss }.map(\.name))
        #expect(Set(missed) == expectedMisses, "misses beyond the known ones: \(Set(missed).subtracting(expectedMisses))")
    }
}

// OpenAI through the real insights request. Skipped unless MINDLORE_OPENAI_KEY is set for the run.
// A measurement of a live model, which answers a little differently each call: it passed 19/19
// on one CI run and filed the haiku as life on the next, with no code between them. On CI it runs
// in the advisory "Live OpenAI tests" job, never in the required unit job (scripts/ci/test.sh).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"]?.isEmpty == false))
struct CreativeOpenAIQualityTests {
    @Test(.timeLimit(.minutes(5)))
    func openAIGetsEveryOneRight() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"])
        let generator = OpenAICompatibleTextGenerator(baseURL: ProviderDefaults.openAIBaseURL, apiKey: key, http: URLSessionHTTPClient())
        var wrong: [String] = []
        try await withThrowingTaskGroup(of: (String, Bool, Bool).self) { group in
            for item in CreativeCorpus.items {
                group.addTask {
                    let plan = InsightsPromptBuilder.plan(text: item.text, source: .typed, sections: InsightSections(), vocabulary: .empty, model: ProviderDefaults.textModel)
                    let answer = try await generator.generate(plan.request)
                    let creative = try InsightsPromptBuilder.parse(answer.text, plan: plan).creative
                    return (item.name, creative, item.creative)
                }
            }
            for try await (name, got, expected) in group where got != expected {
                wrong.append("\(name): got \(got ? "creative" : "life")")
            }
        }
        print("OPENAI CREATIVE wrong=\(wrong)")
        #expect(wrong.isEmpty, "\(wrong)")
    }
}
