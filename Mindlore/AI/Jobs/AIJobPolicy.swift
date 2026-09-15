import Foundation

nonisolated enum AIJob: String, Sendable {
    case text
    case title
    case insights
}

// Shared rules for AI work on an entry. Attempts and the last failure live on the entry, so a
// relaunch never repeats a paid request without limit and never forgets a permanent failure.
enum AIJobPolicy {
    nonisolated static func cap(for job: AIJob) -> Int {
        switch job {
        case .text: 3
        case .title, .insights: 2
        }
    }

    static func isPending(_ job: AIJob, _ entry: Entry) -> Bool {
        switch job {
        case .text: entry.awaitingText
        case .title: entry.titlePending
        case .insights: entry.insightsPending
        }
    }

    static func attempts(_ job: AIJob, _ entry: Entry) -> Int {
        switch job {
        case .text: entry.textAttempts
        case .title: entry.titleAttempts
        case .insights: entry.insightsAttempts
        }
    }

    static func failure(_ job: AIJob, _ entry: Entry) -> AIJobFailure? {
        let raw = switch job {
        case .text: entry.textFailureRaw
        case .title: entry.titleFailureRaw
        case .insights: entry.insightsFailureRaw
        }
        return raw.map(AIJobFailure.init(raw:))
    }

    // Whether automatic processing may send this job now.
    static func canRunAutomatically(_ job: AIJob, _ entry: Entry) -> Bool {
        guard isPending(job, entry), attempts(job, entry) < cap(for: job) else { return false }
        guard let failure = failure(job, entry) else { return true }
        return failure.isRetryable
    }

    // Counted before the request is sent, so a crash mid-request still counts.
    static func recordAttempt(_ job: AIJob, _ entry: Entry) {
        setAttempts(job, entry, attempts(job, entry) + 1)
    }

    static func recordSuccess(_ job: AIJob, _ entry: Entry) {
        setAttempts(job, entry, 0)
        setFailure(job, entry, nil)
        switch job {
        case .text: break
        case .title: entry.titlePending = false
        case .insights: entry.insightsPending = false
        }
    }

    static func recordFailure(_ job: AIJob, _ entry: Entry, _ failure: AIJobFailure) {
        // Nothing reached the server, so the attempt didn't happen.
        if failure.isOffline {
            setAttempts(job, entry, max(0, attempts(job, entry) - 1))
        }
        setFailure(job, entry, failure.raw)
        let stopped = !failure.isRetryable || attempts(job, entry) >= cap(for: job)
        guard stopped else { return }
        switch job {
        // awaitingText still means "no text yet"; the failure and cap stop automatic runs.
        case .text: break
        case .title: entry.titlePending = false
        case .insights: entry.insightsPending = false
        }
    }

    // Retry and Run AI: the user asked, so start over.
    static func manualReset(_ job: AIJob, _ entry: Entry) {
        setAttempts(job, entry, 0)
        setFailure(job, entry, nil)
        switch job {
        case .text: break
        case .title: entry.titlePending = true
        case .insights: entry.insightsPending = true
        }
    }

    private static func setAttempts(_ job: AIJob, _ entry: Entry, _ value: Int) {
        switch job {
        case .text: entry.textAttempts = value
        case .title: entry.titleAttempts = value
        case .insights: entry.insightsAttempts = value
        }
    }

    private static func setFailure(_ job: AIJob, _ entry: Entry, _ raw: String?) {
        switch job {
        case .text: entry.textFailureRaw = raw
        case .title: entry.titleFailureRaw = raw
        case .insights: entry.insightsFailureRaw = raw
        }
    }
}

// A stored failure: "ai.<AIError case>" or "speech.<TranscriptionError case>". Never includes text.
nonisolated struct AIJobFailure: Equatable, Sendable {
    let raw: String

    init(raw: String) {
        self.raw = raw
    }

    init(_ error: AIError) {
        raw = "ai.\(error.caseName)"
    }

    init(_ error: TranscriptionError) {
        if case .provider(let aiError) = error {
            self.init(aiError)
        } else {
            self.init(raw: "speech.\(error.caseName)")
        }
    }

    // Anything thrown on an AI path, reduced to a stored failure.
    init(any error: any Error) {
        switch error {
        case let error as AIError: self.init(error)
        case let error as TranscriptionError: self.init(error)
        default: self.init(raw: "speech.analysisFailed")
        }
    }

    var aiError: AIError? {
        raw.hasPrefix("ai.") ? AIError(caseName: String(raw.dropFirst(3))) : nil
    }

    var transcriptionError: TranscriptionError? {
        if let aiError { return .provider(aiError) }
        return raw.hasPrefix("speech.") ? TranscriptionError(caseName: String(raw.dropFirst(7))) : nil
    }

    var isRetryable: Bool {
        if let aiError { return aiError.isRetryable }
        return transcriptionError.map { !$0.isPermanent } ?? false
    }

    var isOffline: Bool {
        aiError?.isOffline ?? false
    }

    var userMessage: String {
        transcriptionError?.userMessage ?? "Something went wrong."
    }
}
