import Foundation
import SwiftData

// A saved Ask conversation and its turns. Linked by id only, the way EntityLink keeps its truth
// fields, and every property is optional or defaulted so the CloudKit rules hold.
@Model
final class AskConversation {
    var id: UUID = UUID()
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast
    // The first question, trimmed. What the history list shows.
    var title: String = ""
    // JSON ["E1": entry id]. Stable for the conversation, so [E3] means the same entry in every
    // turn and after a reopen.
    var handleMapData: Data?

    init(id: UUID = UUID(), createdAt: Date = .now, title: String = "") {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.title = title
    }

    static let maxTitleCharacters = 80

    static func title(from question: String) -> String {
        let collapsed = question.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(collapsed.prefix(maxTitleCharacters))
    }

    var handleMap: [String: UUID] {
        get {
            guard let handleMapData, let decoded = try? JSONDecoder().decode([String: UUID].self, from: handleMapData) else { return [:] }
            return decoded
        }
        set { handleMapData = try? JSONEncoder().encode(newValue) }
    }

    static func all(in context: ModelContext) -> [AskConversation] {
        ((try? context.fetch(FetchDescriptor<AskConversation>())) ?? []).filter { !$0.isDeleted }
    }

    static func fetch(_ id: UUID, in context: ModelContext) -> AskConversation? {
        let descriptor = FetchDescriptor<AskConversation>(predicate: #Predicate { $0.id == id })
        return ((try? context.fetch(descriptor)) ?? []).first { !$0.isDeleted }
    }
}

nonisolated enum AskRole: String, CaseIterable, Sendable {
    case user, assistant
}

@Model
final class AskMessage {
    var id: UUID = UUID()
    var conversationID: UUID?
    var index: Int = 0
    var roleRaw: String = AskRole.user.rawValue
    var text: String = ""
    // Handles resolved to entry ids. An entry deleted later leaves a dangling id here, which the
    // chip reads as "Entry deleted".
    var citedEntryIDs: [UUID] = []
    var providerLabel: String = ""
    // What "What was sent" shows.
    var sentEntryIDs: [UUID] = []
    var sentCharacters: Int = 0
    // How many entries matched before the cut, and how many months of summary went with them. A
    // reopened conversation cannot work either out again: the index it was answered against is
    // gone. Defaulted and not unique, so the CloudKit rules hold.
    var matchedCount: Int = 0
    var rollupMonthCount: Int = 0
    // AIJobFailure.raw when the answer failed, or "ask.noEntries" when there was nothing to send.
    var failureRaw: String?

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        index: Int,
        role: AskRole,
        text: String,
        citedEntryIDs: [UUID] = [],
        providerLabel: String = "",
        sentEntryIDs: [UUID] = [],
        sentCharacters: Int = 0,
        matchedCount: Int = 0,
        rollupMonthCount: Int = 0,
        failureRaw: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.index = index
        self.roleRaw = role.rawValue
        self.text = text
        self.citedEntryIDs = citedEntryIDs
        self.providerLabel = providerLabel
        self.sentEntryIDs = sentEntryIDs
        self.matchedCount = matchedCount
        self.rollupMonthCount = rollupMonthCount
        self.sentCharacters = sentCharacters
        self.failureRaw = failureRaw
    }

    var role: AskRole {
        get { AskRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var failure: AIJobFailure? {
        failureRaw.map(AIJobFailure.init(raw:))
    }

    static func all(forConversation conversationID: UUID, in context: ModelContext) -> [AskMessage] {
        let wanted: UUID? = conversationID
        let descriptor = FetchDescriptor<AskMessage>(predicate: #Predicate { $0.conversationID == wanted })
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }.sorted { $0.index < $1.index }
    }
}
