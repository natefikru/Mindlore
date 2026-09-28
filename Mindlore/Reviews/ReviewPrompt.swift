import Foundation

// When to ask for an App Store rating (HIG, Ratings and reviews): right after a moment the journal
// was worth something, never in the first days, never twice for one version. The system caps the
// prompt at three a year and decides whether it shows at all, so this only judges the moment.
nonisolated enum ReviewPrompt {
    enum Moment: String {
        // Life showed a full reading, not an early one.
        case lifeReading
        // An entry closed in the editor finished, not a draft.
        case entryFinished
    }

    static let minimumDaysInstalled = 3
    static let minimumFinishedEntries = 10

    static func shouldAsk(
        _ moment: Moment,
        finishedEntries: Int,
        installedAt: Date?,
        lastAskedVersion: String?,
        version: String,
        now: Date
    ) -> Bool {
        guard lastAskedVersion != version, let installedAt else { return false }
        guard now.timeIntervalSince(installedAt) >= Double(minimumDaysInstalled) * 86_400 else { return false }
        switch moment {
        case .lifeReading: return true
        case .entryFinished: return finishedEntries >= minimumFinishedEntries
        }
    }
}

// Carries a good moment to the system's prompt. RootView sets `request` from the environment's
// `requestReview`; until then, and in tests and UI test runs, nothing is shown, though the rule
// still runs.
@Observable
final class ReviewPrompter {
    private let settings: SettingsStore
    private let version: String
    private let now: () -> Date
    private let diagnostics: DiagnosticsLog

    @ObservationIgnored var request: (() -> Void)?

    init(settings: SettingsStore, version: String = ReviewPrompter.bundleVersion, now: @escaping () -> Date = { .now }, diagnostics: DiagnosticsLog = .shared) {
        self.settings = settings
        self.version = version
        self.now = now
        self.diagnostics = diagnostics
    }

    static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    @discardableResult
    func moment(_ moment: ReviewPrompt.Moment, finishedEntries: Int = 0) -> Bool {
        guard ReviewPrompt.shouldAsk(
            moment,
            finishedEntries: finishedEntries,
            installedAt: settings.automationStartedAt,
            lastAskedVersion: settings.reviewRequestedVersion,
            version: version,
            now: now()
        ) else { return false }
        settings.recordReviewRequest(version: version)
        diagnostics.record("review.requested", ["moment": .string(moment.rawValue)])
        request?()
        return true
    }
}
