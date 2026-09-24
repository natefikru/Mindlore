import Foundation
import SwiftData

// Takes a blocked tag (`InsightsPromptBuilder.blockedTags`) out of a journal that already has it:
// from every entry's tags and parts, and off the map, where its links and its entity go. Parsing
// already refuses it, so once this has run it never comes back. Runs in the launch sweep and does
// nothing on a journal without one.
@MainActor
enum BlockedTagSweep {
    // How many records changed.
    @discardableResult
    static func run(in context: ModelContext) -> Int {
        var changed = 0
        for insights in ((try? context.fetch(FetchDescriptor<EntryInsights>())) ?? []) where !insights.isDeleted {
            let tags = insights.tags.filter { !InsightsPromptBuilder.isBlockedTag($0) }
            if tags != insights.tags {
                insights.tags = tags
                changed += 1
            }
            let sections = insights.sections
            let cleaned = sections.map { section in
                var copy = section
                copy.tags = section.tags.filter { !InsightsPromptBuilder.isBlockedTag($0) }
                return copy
            }
            if cleaned != sections {
                insights.sections = cleaned
                changed += 1
            }
        }

        let tagKind = EntityKind.tag.rawValue
        let tagEntities = ((try? context.fetch(FetchDescriptor<Entity>(predicate: #Predicate { $0.kindRaw == tagKind }))) ?? [])
            .filter { !$0.isDeleted && InsightsPromptBuilder.isBlockedTag($0.name) }
        guard !tagEntities.isEmpty else { return changed }
        let blockedIDs = Set(tagEntities.map(\.id))
        for link in ((try? context.fetch(FetchDescriptor<EntityLink>())) ?? []) where !link.isDeleted {
            guard let id = link.entityID, blockedIDs.contains(id) else { continue }
            context.delete(link)
            changed += 1
        }
        // Something merged into it keeps it as a hidden record, so that merge still resolves.
        let mergedInto = Set(((try? context.fetch(FetchDescriptor<Entity>())) ?? []).compactMap(\.mergedIntoID))
        for entity in tagEntities {
            if mergedInto.contains(entity.id) {
                entity.hidden = true
            } else {
                context.delete(entity)
            }
            changed += 1
        }
        return changed
    }
}
