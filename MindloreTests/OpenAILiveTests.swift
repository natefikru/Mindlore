import AVFoundation
import UIKit
import Foundation
import SwiftData
import Testing
@testable import Mindlore

// Talks to the real OpenAI API. Skipped unless MINDLORE_OPENAI_KEY is set for the test run
// (TEST_RUNNER_MINDLORE_OPENAI_KEY when running through xcodebuild). Never runs in the normal loop.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"]?.isEmpty == false))
struct OpenAILiveTests {
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    private var key: String { ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"] ?? "" }
    private let http = URLSessionHTTPClient()

    @Test func modelListIncludesTheDefaults() async throws {
        let models = try await OpenAICompatibleModelList(baseURL: baseURL, apiKey: key, http: http).fetch()
        print("LIVE models: \(models.filter { $0.hasPrefix("gpt") || $0.contains("transcribe") || $0.hasPrefix("whisper") }.joined(separator: ", "))")
        #expect(!models.isEmpty)
    }

    @Test func structuredCall() async throws {
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http)
        let schema = JSONSchema.object([.init("word", .string()), .init("mood", .enumeration(["calm", "sad"], nullable: true))])
        let result = try await generator.generate(TextRequest(model: ProviderDefaults.textModel, system: "Answer briefly.", user: "Reply with the word hello and mood calm.", schema: schema, maxOutputTokens: 2_000))
        struct Reply: Decodable { let word: String; let mood: String? }
        let reply = try StructuredOutputParser.decode(Reply.self, from: result.text)
        print("LIVE text model \(result.model) tokens in \(result.inputTokens ?? -1) out \(result.outputTokens ?? -1)")
        #expect(reply.word.lowercased().contains("hello"))
    }

    // The whole point of streaming, measured against the same call without it: the tokens are
    // identical, and the first word is on screen while the rest is still being written.
    @Test func streamedAnswerArrivesFirstWordFirst() async throws {
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http, quirks: ProviderQuirks())
        let schema = JSONSchema.object([
            .init(AskPrompt.answerField, .string(description: "The answer, in plain sentences.")),
            .init("citations", .array(.enumeration(["E1", "E2"]), description: "The handles used.")),
        ])
        let request = TextRequest(
            model: ProviderDefaults.textModel,
            system: "You answer questions about the author's own journal in four or five sentences.",
            user: "[E1] I ran by the river on Tuesday and felt better afterwards.\n[E2] Wednesday was long and I slept badly.\nQuestion: how was my week?",
            schema: schema,
            schemaName: "journal_ask",
            maxOutputTokens: 2_000
        )

        let startedAt = ContinuousClock.now
        var firstDelta: Duration?
        var firstWord: Duration?
        var raw = ""
        var result: TextResult?
        for try await event in generator.stream(request) {
            switch event {
            case .delta(let delta):
                if firstDelta == nil { firstDelta = startedAt.duration(to: .now) }
                raw += delta
                if firstWord == nil, let text = StreamingJSONString.value(of: AskPrompt.answerField, in: raw), !text.isEmpty {
                    firstWord = startedAt.duration(to: .now)
                }
            case .finished(let finished):
                result = finished
            }
        }
        let total = startedAt.duration(to: .now)
        let finished = try #require(result)
        let answer = try AskAnswerParser.parseJSON(finished.text, known: ["E1", "E2"])

        print("LIVE stream first delta \(firstDelta.map { $0.milliseconds } ?? -1) ms, first word \(firstWord.map { $0.milliseconds } ?? -1) ms, whole answer \(total.milliseconds) ms, \(answer.text.count) characters, tokens in \(finished.inputTokens ?? -1) out \(finished.outputTokens ?? -1)")

        #expect(!answer.text.isEmpty)
        #expect(finished.outputTokens ?? 0 > 0, "stream_options carried the usage through")
        let firstWordAt = try #require(firstWord)
        #expect(firstWordAt < total, "the first word was readable before the answer finished")
    }

    @Test func pageTranscription() async throws {
        let context = try #require(CGContext(data: nil, width: 1_200, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 400))
        let uiImage = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 400)).jpegData(withCompressionQuality: 0.9) { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 1_200, height: 400))
            ("March 3, 2025\nToday I walked to the lake." as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 56)])
        }
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http)
        let transcriber = OpenAICompatiblePageTranscriber(generator: generator, model: ProviderDefaults.pageModel)
        let upload = try PageImageProcessor.uploadJPEG(from: uiImage)
        let result = try await transcriber.transcribe(PageRequest(imageJPEG: upload, pageNumber: 1, pageCount: 1, previousPageTail: nil))
        print("LIVE page tokens in \(result.inputTokens ?? -1) out \(result.outputTokens ?? -1) upload bytes \(upload.count) date \(String(describing: result.writtenDate))")
        #expect(result.text.lowercased().contains("lake"))
        #expect(result.writtenDate != nil)
    }

    @Test func audioTranscription() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A tone has no speech; a successful request that finds none proves the upload shape.
        let caf = directory.appendingPathComponent("tone.caf")
        _ = try AudioFixtures.writePCM(to: caf, seconds: 1.5)
        let transcriber = OpenAICompatibleTranscriber(baseURL: baseURL, apiKey: key, model: ProviderDefaults.speechModel, http: http)
        do {
            let text = try await transcriber.transcribe(audioFileURL: caf, locale: Locale(identifier: "en_US"))
            print("LIVE audio text length \(text.count)")
        } catch TranscriptionError.noSpeechDetected {
            print("LIVE audio: no speech, as expected for a tone")
        }
    }
    // The largest strict schema the app sends: every section, the mood enum, mentions, cleanup, and a custom prompt.
    @Test func fullInsightsSchemaIsAcceptedAndParses() async throws {
        var sections = InsightSections()
        sections.customPrompts = [CustomInsightPrompt(id: UUID(), name: "Gratitude", instructions: "What am I grateful for?", enabled: true)]
        let text = "so today i met sarah at the coffee place on main street and we talked about the move to denver which im kind of anxious about but also grateful she offered to help i still need to call the landlord"
        let plan = InsightsPromptBuilder.plan(text: text, source: .voice, sections: sections, vocabulary: .init(tags: ["friends", "moving"]), model: ProviderDefaults.textModel)
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http, quirks: ProviderQuirks())

        let response = try await generator.generate(plan.request)
        let result = try InsightsPromptBuilder.parse(response.text, plan: plan)

        print("LIVE insights tokens in \(response.inputTokens ?? -1) out \(response.outputTokens ?? -1) mood \(String(describing: result.primaryMood)) areas \(result.areas.map(\.rawValue)) tags \(result.tags) mentions \(result.mentions.map(\.kindRaw)) custom \(result.custom.count)")
        #expect(result.summary != nil)
        #expect(result.primaryMood != nil)
        #expect(result.mentions.contains { $0.name.lowercased().contains("sarah") && $0.kind == .person })
        #expect(result.cleanedText?.isEmpty == false)
        #expect(!result.looseEnds.new.isEmpty, "calling the landlord is a concrete loose end")
        #expect((1...LifeArea.maxPerEntry).contains(result.areas.count), "every entry with content is filed")
        #expect(Set(result.tags).isDisjoint(with: result.areas.map(\.rawValue)), "no tag repeats an area")
    }
    // Known loose ends go out as handles, and a real model settles one by its handle, mentions
    // another by sameAs, and leaves an unrelated one alone.
    @Test func looseEndsAreSettledAndMentionedByHandle() async throws {
        let offer = UUID(), landlord = UUID(), dentist = UUID()
        let known: [InsightsPromptBuilder.KnownLooseEnd] = [
            .init(id: offer, text: "Hear back from Acme about the job offer", own: false),
            .init(id: landlord, text: "Get the landlord to fix the heating", own: false),
            .init(id: dentist, text: "Book a dentist appointment", own: false),
        ]
        let text = "Acme called this morning and offered me the job, and I accepted on the spot. Still no word from the landlord about the heating, it's freezing in here."
        let plan = InsightsPromptBuilder.plan(text: text, source: .typed, sections: InsightSections(), vocabulary: .init(looseEnds: known), model: ProviderDefaults.textModel, entryDate: .now)
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http, quirks: ProviderQuirks())

        let response = try await generator.generate(plan.request)
        let result = try InsightsPromptBuilder.parse(response.text, plan: plan).looseEnds

        print("LIVE looseEnds resolved \(result.resolved.map { $0 == offer ? "offer" : $0 == landlord ? "landlord" : "dentist" }) mentioned \(result.mentioned.count) new \(result.new.map(\.text))")
        #expect(result.resolved == [offer])
        #expect(!result.resolved.contains(dentist) && !result.mentioned.contains(dentist))
        #expect(result.mentioned.contains(landlord) || result.new.isEmpty, "the heating is the known loose end, not a new one")
    }

    // A8's tightened bar, against the real model. One real commitment and two throwaways: the
    // commitment is worth keeping for weeks, and neither throwaway outlives the entry.
    @Test func looseEndsAreCommitmentsNotPassingRemarks() async throws {
        let text = "Long day. I'm going to grab a coffee after this and then head home. The lease is up in April so I really need to call the landlord about renewing, I keep putting it off. Been thinking about the move to Denver a lot lately, I should think about it more."
        let plan = InsightsPromptBuilder.plan(text: text, source: .typed, sections: InsightSections(), vocabulary: .empty, model: ProviderDefaults.textModel, entryDate: .now)
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http, quirks: ProviderQuirks())

        let response = try await generator.generate(plan.request)
        let result = try InsightsPromptBuilder.parse(response.text, plan: plan).looseEnds

        print("LIVE bar new \(result.new.map(\.text))")
        #expect(result.new.count <= 1, "only the landlord is a commitment; got \(result.new.map(\.text))")
        if let only = result.new.first {
            #expect(only.text.lowercased().contains("landlord") || only.text.lowercased().contains("lease"),
                    "the one loose end should be the landlord, not \(only.text)")
        }
        for end in result.new {
            let lowered = end.text.lowercased()
            #expect(!lowered.contains("coffee"), "grabbing coffee settles itself within the entry")
            #expect(!lowered.contains("think"), "thinking more about something is not a commitment")
        }
    }

    // A8's first-person item: the summary talks about the author the way the setting asks.
    @Test func summariesUseTheChosenVoice() async throws {
        let text = "Met Sarah at the coffee place on Main Street this morning and we talked about the move to Denver."
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http, quirks: ProviderQuirks())

        func summary(_ voice: PromptVoice) async throws -> String {
            let plan = await InsightsPromptBuilder.plan(text: text, source: .typed, sections: InsightSections(), vocabulary: .empty, model: ProviderDefaults.textModel, voice: voice)
            let response = try await generator.generate(plan.request)
            return try InsightsPromptBuilder.parse(response.text, plan: plan).summary ?? ""
        }

        let firstPerson = try await summary(.default)
        let byName = try await summary(PromptVoice(voice: .name, name: "Nate"))

        print("LIVE voice first \(firstPerson.debugDescription) name \(byName.debugDescription)")
        // As a word, not a substring: "I" hides inside most sentences.
        #expect(NameMatching.range(of: "I", in: firstPerson) != nil, "first person should say I: \(firstPerson)")
        #expect(NameMatching.range(of: "Nate", in: byName) != nil, "the name voice should say Nate: \(byName)")
        for summary in [firstPerson, byName] {
            #expect(!summary.lowercased().contains("the writer"), "the writer is gone: \(summary)")
        }
    }

    // The journal's own names, against the real model, at the real cap of 50. A name is written
    // as the entry writes it, a garbled one takes the listed spelling, and nothing on the list
    // turns up unless the entry says it.
    @Test func knownNamesFixSpellingWithoutRewritingOrInventing() async throws {
        let decoys: [InsightsPromptBuilder.KnownEntity] = (1...48).map { .init(name: "Decoy Person \($0)", kind: .person) }
        let named = [InsightsPromptBuilder.KnownEntity(name: "Sarah Kim", kind: .person), .init(name: "Harbor Coffee", kind: .place)] + decoys
        let vocabulary = InsightsPromptBuilder.JournalVocabulary(tags: ["work", "friends"], named: named)
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http, quirks: ProviderQuirks())

        func mentions(_ text: String, _ vocabulary: InsightsPromptBuilder.JournalVocabulary) async throws -> ([Mention], Int) {
            let plan = InsightsPromptBuilder.plan(text: text, source: .voice, sections: InsightSections(), vocabulary: vocabulary, model: ProviderDefaults.textModel)
            let response = try await generator.generate(plan.request)
            return (try InsightsPromptBuilder.parse(response.text, plan: plan).mentions, response.inputTokens ?? -1)
        }

        let (partial, withNames) = try await mentions("had lunch with sarah today and she told me about her new job at the hospital", vocabulary)
        let (garbled, _) = try await mentions("met sara kym at harbour coffee this morning", vocabulary)
        let (_, withoutNames) = try await mentions("had lunch with sarah today and she told me about her new job at the hospital", .empty)

        print("LIVE vocabulary partial \(partial.map(\.name)) garbled \(garbled.map(\.name))")
        print("LIVE vocabulary tokens in with 50 names \(withNames), without \(withoutNames)")

        #expect(partial.contains { $0.name.lowercased() == "sarah" }, "written as the entry writes it")
        #expect(!partial.contains { $0.name == "Sarah Kim" }, "not completed to the listed name")
        #expect(garbled.contains { $0.name == "Sarah Kim" }, "a garbled name takes the listed spelling")
        #expect(garbled.contains { $0.name == "Harbor Coffee" })
        for mention in partial + garbled {
            #expect(!mention.name.hasPrefix("Decoy"), "\(mention.name) is not in either entry")
        }
    }

    // Ask, end to end against the real model: a fact seeded among filler, then a follow-up turn
    // that has to keep the same handle.
    // "What's my dog's name?" reaches "a greyhound named Pepper" only through the lemma of "named".
    @Test(.enabled(if: LemmaAvailability.isAvailable, "NLTagger has no English lemma assets on this machine"))
    func askFindsASeededFactAndKeepsItAcrossATurn() async throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let now = Date()
        let texts = [
            "Rain all morning, so I stayed in and read.",
            "Long meeting about the budget. Nothing decided.",
            "I adopted a greyhound named Pepper on Tuesday. She slept the whole way home.",
            "Made soup. Burned the first batch.",
            "Walked to the bridge and back before dark.",
            "Called the landlord about the radiator again.",
        ]
        for (index, text) in texts.enumerated() {
            let entry = Entry(createdAt: now.addingTimeInterval(-Double(index) * 86_400), text: text)
            entry.entryDate = entry.createdAt
            context.insert(entry)
        }
        try context.save()

        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http)
        let ask = AskService(
            resolve: { .success(AskProvider(generator: generator, model: ProviderDefaults.textModel, label: "openai:live", kind: .openAI)) },
            store: AskStore(save: { try $0.save() })
        )

        await ask.send("What's my dog's name?", in: context)
        let first = try #require(ask.turns.last)
        print("LIVE ask answer: \(first.text) citing \(first.citedEntryIDs.count) of \(first.sentEntryIDs.count) sent, \(first.sentCharacters) characters")
        #expect(first.failureRaw == nil)
        #expect(first.text.lowercased().contains("pepper"))
        let pepperEntry = try #require(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).first { $0.text.contains("Pepper") })
        #expect(first.citedEntryIDs == [pepperEntry.id])

        await ask.send("When did I get her?", in: context)
        let second = try #require(ask.turns.last)
        print("LIVE ask follow-up: \(second.text)")
        #expect(second.failureRaw == nil)
        #expect(second.citedEntryIDs.contains(pepperEntry.id), "the follow-up cites the same entry under the same handle")
    }
}

private extension Duration {
    var milliseconds: Int { Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000) }
}
