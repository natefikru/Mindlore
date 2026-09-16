import Foundation
import Observation

@Observable
final class SettingsStore {
    enum Key {
        static let keepAudioAfterTranscription = "keepAudioAfterTranscription"
        static let aiEnabled = "aiEnabled"
        static let aiEnabledAt = "aiEnabledAt"
        static let automationStartedAt = "automationStartedAt"
        static let providerAccounts = "providerAccounts"
        static let speechEngine = "speechEngine"
        static let speechAccountID = "speechAccountID"
        static let speechModel = "speechModel"
        static let fallBackToOnDevice = "fallBackToOnDevice"
        static let pageAccountID = "pageAccountID"
        static let pageModel = "pageModel"
        static let textAccountID = "textAccountID"
        static let textModel = "textModel"
        static let titleGenerator = "titleGenerator"
        static let insightsTrigger = "insightsTrigger"
        static let insightSummary = "insightSummary"
        static let insightMoods = "insightMoods"
        static let insightThemes = "insightThemes"
        static let insightTags = "insightTags"
        static let insightMentions = "insightMentions"
        static let insightOpenThreads = "insightOpenThreads"
        static let insightCleanedText = "insightCleanedText"
        static let autoApplyCleanedText = "autoApplyCleanedText"
        static let suggestEntryDates = "suggestEntryDates"
        static let autoApplySuggestedEntryDate = "autoApplySuggestedEntryDate"
        static let customInsightPrompts = "customInsightPrompts"
    }

    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let onDeviceTitlesAvailable: () -> Bool
    @ObservationIgnored private let onDeviceSpeechAvailable: () -> Bool
    @ObservationIgnored private let now: () -> Date

    var keepAudioAfterTranscription: Bool {
        didSet { write(keepAudioAfterTranscription, Key.keepAudioAfterTranscription, logged: .bool(keepAudioAfterTranscription)) }
    }

    // Turning AI on stamps the time, so recordings made while it was off stay on-device automatically.
    var aiEnabled: Bool {
        didSet {
            write(aiEnabled, Key.aiEnabled, logged: .bool(aiEnabled))
            if aiEnabled && !oldValue {
                aiEnabledAt = now()
                store.set(aiEnabledAt, forKey: Key.aiEnabledAt)
            }
        }
    }

    private(set) var aiEnabledAt: Date?
    private(set) var automationStartedAt: Date?

    // Account names and URLs aren't logged, only that the list changed.
    var providerAccounts: [ProviderAccount] {
        didSet { writeJSON(providerAccounts, Key.providerAccounts) }
    }

    // nil until the user chooses. Apple's live transcription is free, private, and shows text as
    // the user talks, so it leads wherever the phone can run it; OpenAI covers everywhere else.
    private var storedSpeechEngine: SpeechEngine?

    var speechEngine: SpeechEngine {
        get { storedSpeechEngine ?? (onDeviceSpeechAvailable() ? .onDeviceLive : .cloud) }
        set {
            storedSpeechEngine = newValue
            write(newValue.rawValue, Key.speechEngine, logged: .string(newValue.rawValue))
        }
    }

    var speechAccountID: UUID? {
        didSet { write(speechAccountID?.uuidString, Key.speechAccountID) }
    }

    var speechModel: String {
        didSet { write(speechModel, Key.speechModel, logged: .string(speechModel)) }
    }

    var fallBackToOnDevice: Bool {
        didSet { write(fallBackToOnDevice, Key.fallBackToOnDevice, logged: .bool(fallBackToOnDevice)) }
    }

    var pageAccountID: UUID? {
        didSet { write(pageAccountID?.uuidString, Key.pageAccountID) }
    }

    var pageModel: String {
        didSet { write(pageModel, Key.pageModel, logged: .string(pageModel)) }
    }

    var textAccountID: UUID? {
        didSet { write(textAccountID?.uuidString, Key.textAccountID) }
    }

    var textModel: String {
        didSet { write(textModel, Key.textModel, logged: .string(textModel)) }
    }

    // nil until the user chooses. With AI set up, titles come from the provider like the rest of the
    // AI work; otherwise the free on-device model writes them, and failing that nothing does.
    private var storedTitleGenerator: TitleGenerator?

    var titleGenerator: TitleGenerator {
        get {
            if let storedTitleGenerator { return storedTitleGenerator }
            if aiEnabled && !providerAccounts.isEmpty { return .openAI }
            return onDeviceTitlesAvailable() ? .onDevice : .off
        }
        set {
            storedTitleGenerator = newValue
            write(newValue.rawValue, Key.titleGenerator, logged: .string(newValue.rawValue))
        }
    }

    var insightsTrigger: InsightsTrigger {
        didSet { write(insightsTrigger.rawValue, Key.insightsTrigger, logged: .string(insightsTrigger.rawValue)) }
    }

    var insightSummary: Bool { didSet { write(insightSummary, Key.insightSummary, logged: .bool(insightSummary)) } }
    var insightMoods: Bool { didSet { write(insightMoods, Key.insightMoods, logged: .bool(insightMoods)) } }
    var insightThemes: Bool { didSet { write(insightThemes, Key.insightThemes, logged: .bool(insightThemes)) } }
    var insightTags: Bool { didSet { write(insightTags, Key.insightTags, logged: .bool(insightTags)) } }
    var insightMentions: Bool { didSet { write(insightMentions, Key.insightMentions, logged: .bool(insightMentions)) } }
    var insightOpenThreads: Bool { didSet { write(insightOpenThreads, Key.insightOpenThreads, logged: .bool(insightOpenThreads)) } }
    var insightCleanedText: Bool { didSet { write(insightCleanedText, Key.insightCleanedText, logged: .bool(insightCleanedText)) } }
    var autoApplyCleanedText: Bool { didSet { write(autoApplyCleanedText, Key.autoApplyCleanedText, logged: .bool(autoApplyCleanedText)) } }
    var suggestEntryDates: Bool { didSet { write(suggestEntryDates, Key.suggestEntryDates, logged: .bool(suggestEntryDates)) } }
    var autoApplySuggestedEntryDate: Bool { didSet { write(autoApplySuggestedEntryDate, Key.autoApplySuggestedEntryDate, logged: .bool(autoApplySuggestedEntryDate)) } }

    // Prompt names and instructions are the user's own words, so only the change is logged.
    var customInsightPrompts: [CustomInsightPrompt] {
        didSet { writeJSON(customInsightPrompts, Key.customInsightPrompts) }
    }

    // Reads go through object(forKey:) so a missing key means "use the default" rather than false.
    init(
        store: any KeyValueStore = UserDefaults.standard,
        diagnostics: DiagnosticsLog = .shared,
        onDeviceTitlesAvailable: @escaping () -> Bool = { false },
        onDeviceSpeechAvailable: @escaping () -> Bool = { false },
        now: @escaping () -> Date = { .now }
    ) {
        self.store = store
        self.diagnostics = diagnostics
        self.onDeviceTitlesAvailable = onDeviceTitlesAvailable
        self.onDeviceSpeechAvailable = onDeviceSpeechAvailable
        self.now = now

        func bool(_ key: String, _ fallback: Bool) -> Bool { store.object(forKey: key) as? Bool ?? fallback }
        func string(_ key: String) -> String? { store.object(forKey: key) as? String }
        func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }
        func json<T: Decodable>(_ key: String, _ fallback: T) -> T {
            (store.object(forKey: key) as? Data).flatMap { try? JSONDecoder().decode(T.self, from: $0) } ?? fallback
        }

        keepAudioAfterTranscription = bool(Key.keepAudioAfterTranscription, true)
        aiEnabled = bool(Key.aiEnabled, false)
        aiEnabledAt = store.object(forKey: Key.aiEnabledAt) as? Date
        automationStartedAt = store.object(forKey: Key.automationStartedAt) as? Date
        providerAccounts = json(Key.providerAccounts, [])
        storedSpeechEngine = string(Key.speechEngine).flatMap(SpeechEngine.init(rawValue:))
        speechAccountID = uuid(Key.speechAccountID)
        speechModel = string(Key.speechModel) ?? ProviderDefaults.speechModel
        fallBackToOnDevice = bool(Key.fallBackToOnDevice, true)
        pageAccountID = uuid(Key.pageAccountID)
        pageModel = string(Key.pageModel) ?? ProviderDefaults.pageModel
        textAccountID = uuid(Key.textAccountID)
        textModel = string(Key.textModel) ?? ProviderDefaults.textModel
        storedTitleGenerator = string(Key.titleGenerator).flatMap(TitleGenerator.init(rawValue:))
        insightsTrigger = string(Key.insightsTrigger).flatMap(InsightsTrigger.init(rawValue:)) ?? .automatic
        insightSummary = bool(Key.insightSummary, true)
        insightMoods = bool(Key.insightMoods, true)
        insightThemes = bool(Key.insightThemes, true)
        insightTags = bool(Key.insightTags, true)
        insightMentions = bool(Key.insightMentions, true)
        insightOpenThreads = bool(Key.insightOpenThreads, true)
        insightCleanedText = bool(Key.insightCleanedText, true)
        autoApplyCleanedText = bool(Key.autoApplyCleanedText, false)
        suggestEntryDates = bool(Key.suggestEntryDates, true)
        autoApplySuggestedEntryDate = bool(Key.autoApplySuggestedEntryDate, false)
        customInsightPrompts = json(Key.customInsightPrompts, [])
    }

    // Called once per launch. Entries created before this moment never get an automatic AI pass.
    func recordAutomationStartIfNeeded() {
        guard automationStartedAt == nil else { return }
        let started = now()
        automationStartedAt = started
        store.set(started, forKey: Key.automationStartedAt)
    }

    func account(for capability: AICapability) -> ProviderAccount? {
        let id: UUID? = switch capability {
        case .speech: speechAccountID
        case .pages: pageAccountID
        case .text: textAccountID
        }
        return providerAccounts.first { $0.id == id }
    }

    func model(for capability: AICapability) -> String {
        switch capability {
        case .speech: speechModel
        case .pages: pageModel
        case .text: textModel
        }
    }

    private func write(_ value: Any?, _ key: String, logged: DiagnosticValue? = nil) {
        store.set(value, forKey: key)
        var fields: [String: DiagnosticValue] = ["key": .string(key)]
        fields["value"] = logged
        diagnostics.record("settings.changed", fields)
    }

    private func writeJSON<T: Encodable>(_ value: T, _ key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
        diagnostics.record("settings.changed", ["key": .string(key)])
    }
}
