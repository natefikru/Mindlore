import AVFoundation
import UIKit
import Foundation
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
        sections.customPrompts = [CustomInsightPrompt(id: UUID(), name: "Gratitude", instructions: "What is the writer grateful for?", enabled: true)]
        let text = "so today i met sarah at the coffee place on main street and we talked about the move to denver which im kind of anxious about but also grateful she offered to help i still need to call the landlord"
        let plan = InsightsPromptBuilder.plan(text: text, source: .voice, sections: sections, vocabulary: .init(tags: ["friends", "moving"]), model: ProviderDefaults.textModel)
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http, jsonModeMemory: JSONModeMemory())

        let response = try await generator.generate(plan.request)
        let result = try InsightsPromptBuilder.parse(response.text, plan: plan)

        print("LIVE insights tokens in \(response.inputTokens ?? -1) out \(response.outputTokens ?? -1) mood \(String(describing: result.primaryMood)) areas \(result.areas.map(\.rawValue)) tags \(result.tags) mentions \(result.mentions.map(\.kindRaw)) custom \(result.custom.count)")
        #expect(result.summary != nil)
        #expect(result.primaryMood != nil)
        #expect(result.mentions.contains { $0.name.lowercased().contains("sarah") && $0.kind == .person })
        #expect(result.cleanedText?.isEmpty == false)
        #expect(!result.openThreads.isEmpty)
        #expect((1...LifeArea.maxPerEntry).contains(result.areas.count), "every entry with content is filed")
    }
    // The journal's own names, against the real model, at the real cap of 50. A name is written
    // as the entry writes it, a garbled one takes the listed spelling, and nothing on the list
    // turns up unless the entry says it.
    @Test func knownNamesFixSpellingWithoutRewritingOrInventing() async throws {
        let decoys: [InsightsPromptBuilder.KnownEntity] = (1...48).map { .init(name: "Decoy Person \($0)", kind: .person) }
        let named = [InsightsPromptBuilder.KnownEntity(name: "Sarah Kim", kind: .person), .init(name: "Harbor Coffee", kind: .place)] + decoys
        let vocabulary = InsightsPromptBuilder.JournalVocabulary(tags: ["work", "friends"], named: named)
        let generator = OpenAICompatibleTextGenerator(baseURL: baseURL, apiKey: key, http: http, jsonModeMemory: JSONModeMemory())

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
}
