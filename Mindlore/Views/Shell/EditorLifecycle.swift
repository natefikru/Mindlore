import Foundation
import SwiftData

// What happens when an entry is opened in the editor and when it leaves Journal's path: presence,
// delete-if-blank, discarding audio that isn't kept, and the automatic AI pass.
final class EditorLifecycle {
    private let context: ModelContext
    private let saver: EntrySaver
    private let presence: EditorPresence
    private let aiPass: AIPassTrigger
    private let keepAudio: () -> Bool
    private let diagnostics: DiagnosticsLog

    init(
        context: ModelContext,
        saver: EntrySaver,
        presence: EditorPresence,
        aiPass: AIPassTrigger,
        keepAudio: @escaping () -> Bool,
        diagnostics: DiagnosticsLog = .shared
    ) {
        self.context = context
        self.saver = saver
        self.presence = presence
        self.aiPass = aiPass
        self.keepAudio = keepAudio
        self.diagnostics = diagnostics
    }

    func opened(_ id: UUID) {
        presence.open(id)
    }

    func closed(_ id: UUID) {
        closed(id, firesAIPass: true)
    }

    // Deleted from the editor's menu. The delete waits behind Undo, so everything else a close
    // does still happens, but no AI pass starts for an entry that is on its way out.
    func closedForDeletion(_ id: UUID) {
        closed(id, firesAIPass: false)
    }

    private func closed(_ id: UUID, firesAIPass: Bool) {
        presence.close(id)
        // A new route the user never typed into has no entry.
        if let entry = Self.entry(id, in: context) {
            let hadAudio = entry.audioData != nil
            let deleted = Entry.editorDidClose(entry, keepAudio: keepAudio(), in: context)
            diagnostics.record("editor.closed", [
                "id": .id(id),
                "deleted": .bool(deleted),
                "audioDiscarded": .bool(hadAudio && (deleted || entry.audioData == nil)),
                "characters": .int(deleted ? 0 : entry.text.count),
            ])
            if !deleted && firesAIPass {
                aiPass.fire(for: entry, at: .editorClosed)
            }
        }
        saver.flush()
        if firesAIPass { aiPass.onFlagged?() }
    }

    // Includes unsaved inserts, so an entry created moments ago is found.
    static func entry(_ id: UUID, in context: ModelContext) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
