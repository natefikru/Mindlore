import Foundation
import Observation
import SwiftData

// Injected so tests never wait on real tokenizing, and @concurrent on the requirement rather than
// nonisolated alone: SWIFT_APPROACHABLE_CONCURRENCY turns on NonisolatedNonsendingByDefault, so a
// nonisolated async function runs on the caller's actor. A8's review found that the hard way with
// CNContactStore. Mindlore/Contacts/ContactDirectory.swift is the pattern.
nonisolated protocol AskIndexBuilding: Sendable {
    @concurrent func build(_ inputs: [AskIndex.DocumentInput], entities: [AskIndex.Entity]) async -> AskIndex
}

nonisolated struct AskIndexBuilder: AskIndexBuilding {
    @concurrent func build(_ inputs: [AskIndex.DocumentInput], entities: [AskIndex.Entity]) async -> AskIndex {
        AskIndex.build(from: inputs, entities: entities)
    }
}

// Holds the one index Ask and the search panel both read, and decides when it is stale.
//
// The point is what it stops doing. Today AskSources.journal fetches every Entry, EntityLink, and
// Entity with no predicate, no limit, and no cache, and the cost line under the field calls it on a
// debounce: every pause in typing reads the whole journal on the main actor. Here the journal is
// read once when Ask appears and again only when something actually changed, and the estimate
// reads a snapshot.
@Observable
@MainActor
final class AskIndexStore {
    // The counters that between them see every change. Passed in rather than held, so the store owes
    // nothing to EntrySaver, GraphServices, or the save path.
    //
    // `stamped` is the one that catches the rest. The three transcription and title coordinators
    // save straight through saveStampingEntries, bumping neither of the others, so without it a
    // recording's text never reached the index and asking about the entry you just recorded
    // answered "nothing to go on" for the rest of the session.
    nonisolated struct Revisions: Equatable, Sendable {
        var saver = 0
        var graph = 0
        var stamped = 0
    }

    // Ordinals only. An earlier draft used max(Entry.updatedAt) and would have gone blind to a clock
    // stepping back or an entry restored with an older stamp, which is the hole Entry.graphIndexedAt
    // already exists to avoid.
    nonisolated struct Fingerprint: Equatable, Sendable {
        var entries = 0
        var links = 0
        var entities = 0
        var revisions = Revisions()
    }

    private(set) var index = AskIndex.empty

    @ObservationIgnored private let builder: any AskIndexBuilding
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private(set) var built: Fingerprint?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    // nonisolated so it can be a default argument of AskService's own initializer, the way AskStore
    // is.
    nonisolated init(
        builder: any AskIndexBuilding = AskIndexBuilder(),
        diagnostics: DiagnosticsLog = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.builder = builder
        self.diagnostics = diagnostics
        self.now = now
    }

    func refreshIfNeeded(revisions: Revisions, in context: ModelContext) async {
        // Ask appears and then a question is sent a moment later. Without this the journal is read
        // twice for one intent.
        if let running = inFlight { await running.value }

        let fingerprint = Self.fingerprint(revisions: revisions, in: context)
        guard fingerprint != built else { return }

        let task = Task { await self.rebuild(fingerprint: fingerprint, in: context) }
        inFlight = task
        await task.value
        if inFlight == task { inFlight = nil }
    }

    private func rebuild(fingerprint: Fingerprint, in context: ModelContext) async {
        let startedAt = now()
        // The one main-actor pass. It reads every entry and faults each entry's insights for tags,
        // areas, and mood, so it costs more than the old journal fetch did; it is paid once when Ask
        // appears instead of on every pause in typing. A background ModelActor would remove even
        // that, and is deliberately not in this phase. fetchMilliseconds is logged so the decision
        // later comes off a number.
        let gathered = AskSources.documents(in: context)
        let fetchedAt = now()

        index = await builder.build(gathered.documents, entities: gathered.entities)
        built = fingerprint

        diagnostics.record("ask.indexed", [
            "documents": .int(gathered.documents.count),
            "sendable": .int(gathered.documents.count { $0.isSendable }),
            "entities": .int(gathered.entities.count),
            "terms": .int(index.termCount),
            "postings": .int(index.postingCount),
            "fetchMilliseconds": .int(Int(fetchedAt.timeIntervalSince(startedAt) * 1000)),
            "durationMilliseconds": .int(Int(now().timeIntervalSince(startedAt) * 1000)),
        ])
    }

    static func fingerprint(revisions: Revisions, in context: ModelContext) -> Fingerprint {
        Fingerprint(
            entries: (try? context.fetchCount(FetchDescriptor<Entry>())) ?? -1,
            links: (try? context.fetchCount(FetchDescriptor<EntityLink>())) ?? -1,
            entities: (try? context.fetchCount(FetchDescriptor<Entity>())) ?? -1,
            revisions: revisions
        )
    }
}
