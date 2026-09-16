import Foundation
import SwiftData
import Observation

// The one graph object the app shares. RootView builds it once and puts it in the environment,
// so views and coordinators use the same indexer, editor, and log instead of building their own.
//
// `revision` moves after every change the graph makes on a view's behalf; screens that show
// entities use it as their refresh key.
@MainActor
@Observable
final class GraphServices {
    let indexer: GraphIndexer
    let editor: GraphEditor
    private(set) var revision = 0

    init(diagnostics: DiagnosticsLog = .shared) {
        indexer = GraphIndexer(diagnostics: diagnostics)
        editor = GraphEditor(diagnostics: diagnostics)
    }

    // Call after the deletion is saved, so the cascade has taken the entries' links with it.
    // Whatever nobody mentions any more goes too.
    func entriesDeleted(in context: ModelContext) {
        indexer.recount(in: context)
        revision += 1
    }

    func insightsDeleted(for entry: Entry, in context: ModelContext) {
        entry.removeInsights(in: context)
        indexer.recount(in: context)
        revision += 1
    }

    // The counters are dated by the entry, so moving one moves them.
    func entryDateChanged(in context: ModelContext) {
        indexer.recount(in: context)
        revision += 1
    }

    // After an insights run wrote this entry. The coordinator saves afterwards, and the bump
    // lets an open sheet pick up the new links.
    func insightsWritten(for entry: Entry, in context: ModelContext) {
        indexer.index(entry, in: context)
        indexer.recount(in: context)
        revision += 1
    }
}
