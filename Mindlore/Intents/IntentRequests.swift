import Foundation
import Observation

// Something Siri, Shortcuts, or the Action button asked the app to do.
nonisolated enum IntentAction: Equatable, Sendable {
    case record
    case newEntry
    // A question to put in Ask's field, or nil to open Ask with the field empty. Never sent on its
    // own: asking costs a request, so the user sends it.
    case ask(String?)

    // For diagnostics: which action, never what the question said.
    var kind: String {
        switch self {
        case .record: "record"
        case .newEntry: "newEntry"
        case .ask: "ask"
        }
    }
}

// Where an intent leaves its request for the app to pick up. It has to stand apart from RootView:
// an intent can run on a cold launch, before RootView has built the recorder, the router, or Ask,
// so there is nothing yet to hand the request to. RootView takes it when it appears and whenever a
// new one arrives, so a cold launch and a warm one take the same path, exactly once.
@MainActor
@Observable
final class IntentRequests {
    static let shared = IntentRequests()

    private(set) var pending: IntentAction?
    // Moves on every request, so asking twice for the same thing still counts as two.
    private(set) var token = 0

    @ObservationIgnored private let diagnostics: DiagnosticsLog

    init(diagnostics: DiagnosticsLog = .shared) {
        self.diagnostics = diagnostics
    }

    func request(_ action: IntentAction) {
        pending = action
        token += 1
        var fields: [String: DiagnosticValue] = ["kind": .string(action.kind)]
        if case .ask(let question) = action {
            fields["hasQuestion"] = .bool(!(question ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        diagnostics.record("intent.invoked", fields)
    }

    // Hands the request over once and forgets it, so a view that appears twice acts once.
    func take() -> IntentAction? {
        defer { pending = nil }
        return pending
    }
}

// What an intent does once the app has the objects to do it with. Every action goes through a call
// the app's own buttons already use, so an intent can't reach a state a tap couldn't.
@MainActor
enum IntentHandler {
    enum Outcome: Equatable {
        case recording
        // A recording was already running, so the recorder came back instead of a second starting.
        case recorderShown
        case newEntry
        case ask
    }

    @discardableResult
    static func handle(_ action: IntentAction, recording: RecordingSession, router: AppRouter) -> Outcome {
        switch action {
        case .record:
            guard recording.status == .idle else {
                recording.expand()
                return .recorderShown
            }
            recording.begin()
            return .recording
        case .newEntry:
            router.showNewEntry()
            return .newEntry
        case .ask(let question):
            router.showAsk(question: question)
            return .ask
        }
    }
}
