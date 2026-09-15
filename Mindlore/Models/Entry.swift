import Foundation
import SwiftData

// CloudKit sync requires every stored property to be optional or have a default,
// and forbids unique constraints. CloudKitSchemaRulesTests enforces this.
@Model
final class Entry {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var sourceRaw: String = EntrySource.typed.rawValue
    var text: String = ""
    var textEditedByUser: Bool = false
    var awaitingText: Bool = false
    @Attribute(.externalStorage) var audioData: Data?
    var audioDuration: Double?

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .typed }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        source: EntrySource = .typed,
        text: String = "",
        awaitingText: Bool = false,
        audioData: Data? = nil,
        audioDuration: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.sourceRaw = source.rawValue
        self.text = text
        self.awaitingText = awaitingText
        self.audioData = audioData
        self.audioDuration = audioDuration
    }
}
