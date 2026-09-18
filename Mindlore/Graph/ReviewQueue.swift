import Foundation

// The one question Mind's panel asks at a time. "Which one?" comes first, since it's about a
// sentence the user actually wrote; then "likely the same" pairs in EntityMatcher's order.
// Skipping is remembered for the session only and writes nothing.
enum ReviewQueue {
    enum Question: Identifiable {
        case same(a: UUID, b: UUID)
        case whichOne(GraphServices.UnsureMention)

        var id: String {
            switch self {
            case .same(let a, let b):
                "same:\(a.uuidString):\(b.uuidString)"
            case .whichOne(let unsure):
                "which:\(unsure.mention.entryID.uuidString):\(unsure.mention.kind.rawValue):\(unsure.mention.surface)"
            }
        }
    }

    static func next(suggestions: [EntityMatcher.Suggestion], unsure: [GraphServices.UnsureMention], skipped: Set<String>) -> Question? {
        let questions = unsure.map(Question.whichOne) + suggestions.map { Question.same(a: $0.a, b: $0.b) }
        return questions.first { !skipped.contains($0.id) }
    }
}
