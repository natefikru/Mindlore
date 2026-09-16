import Foundation
import SwiftData

// Drafts one neutral sentence about an entity from the sentences that name it. Only text the
// provider has already received in full for insights is quoted, and nothing else about the
// entity (its bio, aliases, or neighbours) is sent.
@MainActor
struct EntityBioDrafter {
    let diagnostics: DiagnosticsLog

    init(diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
    }

    // Only kinds whose names appear word for word in entries are drafted without being asked.
    static let automaticKinds: Set<EntityKind> = [.person, .place, .organization, .project, .event]

    nonisolated static let schemaName = "entity_bio"
    static let schema = JSONSchema.object([.init("bio", .string(nullable: true))])

    enum Outcome: Equatable {
        case drafted
        // The model said the excerpts were not enough; recorded, so it is not asked again.
        case notEnough
        // Nothing names the entity in text the provider has seen; nothing was sent.
        case noExcerpts
        // The entity is gone, merged, or the user's bio is in the way.
        case skipped
        case cancelled
        case failed(AIJobFailure)
    }

    // AI may write the bio only while it is empty or its own, and never after the user touched it.
    static func mayWrite(_ entity: Entity) -> Bool {
        !entity.isMerged && !entity.bioEditedByUser && (entity.bio == nil || entity.bioWasGenerated)
    }

    func excerpts(for entityID: UUID, in context: ModelContext) -> BioExcerpts.Selection {
        let links = ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? [])
            .filter { $0.entityID == entityID && !$0.isDeleted }
        let surfaces = Dictionary(grouping: links.compactMap { link in link.entryID.map { ($0, link.surface) } }, by: \.0)
            .mapValues { $0.map(\.1) }
        guard !surfaces.isEmpty else { return BioExcerpts.Selection() }
        let ids = Set(surfaces.keys)
        let entries = ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { ids.contains($0.id) }))) ?? [])
            .filter(Self.wasSentInFull)
        return BioExcerpts.select(from: entries.map { entry in
            BioExcerpts.Source(
                text: String(entry.text.prefix(InsightsPromptBuilder.maxInputCharacters)),
                date: entry.entryDate,
                surfaces: surfaces[entry.id] ?? []
            )
        })
    }

    // The insights request for this exact text went out, so quoting it discloses nothing new.
    static func wasSentInFull(_ entry: Entry) -> Bool {
        guard !entry.isDeleted, !entry.isAwaitingPageConfirmation, InsightsCoordinator.canRunAI(on: entry),
              let insights = entry.insights else { return false }
        return insights.isCurrent(for: entry)
    }

    static func request(name: String, kind: EntityKind, excerpts: BioExcerpts.Selection, model: String) -> TextRequest? {
        guard let name = InsightsPromptBuilder.promptSafe(name) else { return nil }
        let system = """
        Based only on how \(name) is described in these excerpts from the writer's journal, write one \
        neutral sentence about who or what \(name) is to the writer. Do not speculate beyond what is said. \
        Return null if the excerpts do not say enough.
        """
        let user = "Name: \(name)\nKind: \(kind.rawValue)\nExcerpts:\n" + excerpts.sentences.map { "- \($0)" }.joined(separator: "\n")
        return TextRequest(model: model, system: system, user: user, schema: schema, schemaName: schemaName, maxOutputTokens: 300)
    }

    func draft(entityID: UUID, using generator: ResolvedTextGenerator, in context: ModelContext) async -> Outcome {
        guard let entity = Self.fetch(entityID, in: context), Self.mayWrite(entity) else { return .skipped }
        let excerpts = excerpts(for: entityID, in: context)
        guard !excerpts.isEmpty else { return .noExcerpts }
        guard let request = Self.request(name: entity.name, kind: entity.kind, excerpts: excerpts, model: generator.model) else {
            return .skipped
        }

        let result: TextResult
        let bio: String?
        do {
            result = try await generator.generator.generate(request)
            bio = try StructuredOutputParser.decode(Response.self, from: result.text).bio?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            if Task.isCancelled { return .cancelled }
            let failure = AIJobFailure(any: error)
            diagnostics.record("graph.bioFailed", ["id": .id(entityID), "error": .string(failure.raw)])
            return .failed(failure)
        }
        guard !Task.isCancelled else { return .cancelled }

        // Anything could have happened while the request was out.
        guard let current = Self.fetch(entityID, in: context), Self.mayWrite(current) else { return .skipped }
        let written = (bio?.isEmpty ?? true) ? nil : bio
        current.bio = written
        current.bioWasGenerated = true
        current.bioDraftedAt = .now
        current.bioModelUsed = result.model.isEmpty ? generator.model : result.model
        current.bioSourceEntries = excerpts.entries
        current.bioSourceCharacters = excerpts.characters
        // A plain save: nothing here touched an entry, and exempting one could hide a real edit.
        do {
            try context.saveStampingEntries()
        } catch {
            diagnostics.record("graph.saveFailed", ["error": .errorCode(error)])
        }
        diagnostics.record("graph.bioDrafted", [
            "id": .id(entityID),
            "entries": .int(excerpts.entries),
            "characters": .int(excerpts.characters),
            "empty": .bool(written == nil),
            "inputTokens": .int(result.inputTokens ?? -1),
            "outputTokens": .int(result.outputTokens ?? -1),
        ])
        return written == nil ? .notEnough : .drafted
    }

    private struct Response: Decodable {
        let bio: String?
    }

    private static func fetch(_ id: UUID, in context: ModelContext) -> Entity? {
        var descriptor = FetchDescriptor<Entity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first { !$0.isDeleted }
    }
}
