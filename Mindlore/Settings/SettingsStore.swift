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
        static let insightsGenerator = "insightsGenerator"
        static let askGenerator = "askGenerator"
        static let askGeneratorChosenByUser = "askGeneratorChosenByUser"
        static let insightsTrigger = "insightsTrigger"
        static let insightSummary = "insightSummary"
        static let insightMoods = "insightMoods"
        static let insightLifeAreas = "insightLifeAreas"
        static let insightTags = "insightTags"
        static let insightMentions = "insightMentions"
        static let insightLooseEnds = "insightLooseEnds"
        static let insightCleanedText = "insightCleanedText"
        static let autoApplyCleanedText = "autoApplyCleanedText"
        static let suggestEntryDates = "suggestEntryDates"
        static let autoApplySuggestedEntryDate = "autoApplySuggestedEntryDate"
        static let customInsightPrompts = "customInsightPrompts"
        static let lifeAreaNames = "lifeAreaNames"
        static let hiddenLifeAreas = "hiddenLifeAreas"
        static let journalVoice = "journalVoice"
        static let appearance = "appearance"
        static let userName = "userName"
        static let resurfacingEnabled = "resurfacingEnabled"
        static let reminderEnabled = "reminderEnabled"
        static let reminderMinutes = "reminderMinutes"
        static let todayDismissed = "todayDismissed"
        static let reflectDismissed = "reflectDismissed"
        static let appLockEnabled = "appLockEnabled"
        static let welcomeSeen = "welcomeSeen"
    }

    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let diagnostics: DiagnosticsLog
    @ObservationIgnored private let onDeviceTitlesAvailable: () -> Bool
    @ObservationIgnored private let onDeviceSpeechAvailable: () -> Bool
    @ObservationIgnored private let now: () -> Date

    var keepAudioAfterTranscription: Bool {
        didSet { write(keepAudioAfterTranscription, Key.keepAudioAfterTranscription, logged: .bool(keepAudioAfterTranscription)) }
    }

    // Internal state, never a control: the first-run screen has been shown (or skipped because the
    // journal already had entries).
    var welcomeSeen: Bool {
        didSet { write(welcomeSeen, Key.welcomeSeen) }
    }

    // Face ID or the passcode whenever the app comes back from the background. Off by default.
    var appLockEnabled: Bool {
        didSet { write(appLockEnabled, Key.appLockEnabled, logged: .bool(appLockEnabled)) }
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

    // nil until the user chooses, and resolved like titles: OpenAI once AI is set up, the free
    // on-device model otherwise, nothing on a phone that has neither (owner, 2026-09-22).
    private var storedInsightsGenerator: InsightsGenerator?

    var insightsGenerator: InsightsGenerator {
        get {
            if let storedInsightsGenerator { return storedInsightsGenerator }
            if aiEnabled && !providerAccounts.isEmpty { return .openAI }
            return onDeviceTitlesAvailable() ? .onDevice : .off
        }
        set {
            storedInsightsGenerator = newValue
            write(newValue.rawValue, Key.insightsGenerator, logged: .string(newValue.rawValue))
        }
    }

    // Where a question goes. Until the user picks in Settings this follows the phone: it answers
    // on device while that's all there is, and hands over to OpenAI as soon as a key is saved
    // (owner, 2026-09-18). The moment the user picks, that choice is theirs and nothing moves it.
    private var storedAskGenerator: AskGenerator?
    private var askGeneratorChosenByUser: Bool

    var askGenerator: AskGenerator {
        get { storedAskGenerator ?? .off }
        set {
            storedAskGenerator = newValue
            write(newValue.rawValue, Key.askGenerator, logged: .string(newValue.rawValue))
            guard !askGeneratorChosenByUser else { return }
            askGeneratorChosenByUser = true
            store.set(true, forKey: Key.askGeneratorChosenByUser)
        }
    }

    var hasChosenAskGenerator: Bool { askGeneratorChosenByUser }

    // Called every time Ask opens, so allowing AI with a key saved later moves questions to OpenAI
    // without the user having to go and find the setting.
    @discardableResult
    func refreshAskGeneratorDefault(textUsable: Bool, onDeviceAvailable: Bool) -> AskGenerator {
        guard !askGeneratorChosenByUser else { return askGenerator }
        let chosen: AskGenerator = textUsable ? .openAI : (onDeviceAvailable ? .onDevice : .off)
        guard chosen != storedAskGenerator else { return chosen }
        storedAskGenerator = chosen
        write(chosen.rawValue, Key.askGenerator, logged: .string(chosen.rawValue))
        return chosen
    }

    var insightsTrigger: InsightsTrigger {
        didSet { write(insightsTrigger.rawValue, Key.insightsTrigger, logged: .string(insightsTrigger.rawValue)) }
    }

    var insightSummary: Bool { didSet { write(insightSummary, Key.insightSummary, logged: .bool(insightSummary)) } }
    var insightMoods: Bool { didSet { write(insightMoods, Key.insightMoods, logged: .bool(insightMoods)) } }
    var insightLifeAreas: Bool { didSet { write(insightLifeAreas, Key.insightLifeAreas, logged: .bool(insightLifeAreas)) } }
    var insightTags: Bool { didSet { write(insightTags, Key.insightTags, logged: .bool(insightTags)) } }
    var insightMentions: Bool { didSet { write(insightMentions, Key.insightMentions, logged: .bool(insightMentions)) } }
    var insightLooseEnds: Bool { didSet { write(insightLooseEnds, Key.insightLooseEnds, logged: .bool(insightLooseEnds)) } }
    var insightCleanedText: Bool { didSet { write(insightCleanedText, Key.insightCleanedText, logged: .bool(insightCleanedText)) } }
    var autoApplyCleanedText: Bool { didSet { write(autoApplyCleanedText, Key.autoApplyCleanedText, logged: .bool(autoApplyCleanedText)) } }
    var suggestEntryDates: Bool { didSet { write(suggestEntryDates, Key.suggestEntryDates, logged: .bool(suggestEntryDates)) } }
    var autoApplySuggestedEntryDate: Bool { didSet { write(autoApplySuggestedEntryDate, Key.autoApplySuggestedEntryDate, logged: .bool(autoApplySuggestedEntryDate)) } }

    // Prompt names and instructions are the user's own words, so only the change is logged.
    var customInsightPrompts: [CustomInsightPrompt] {
        didSet { writeJSON(customInsightPrompts, Key.customInsightPrompts) }
    }

    // Renames are the user's own words, so only the change is logged. Keyed by raw value; the
    // model and storage always use raw values.
    var lifeAreaNames: [String: String] {
        didSet { writeJSON(lifeAreaNames, Key.lifeAreaNames) }
    }

    // A hidden area drops out of chips and filters, but entries keep it, so showing it again
    // brings its entries back.
    var hiddenLifeAreas: Set<String> {
        didSet { writeJSON(hiddenLifeAreas, Key.hiddenLifeAreas) }
    }

    var journalVoice: JournalVoice { didSet { write(journalVoice.rawValue, Key.journalVoice, logged: .string(journalVoice.rawValue)) } }

    var appearance: AppearancePreference {
        didSet { write(appearance.rawValue, Key.appearance, logged: .string(appearance.rawValue)) }
    }

    // The user's own name, so only the change is logged, never the value. It reaches the AI
    // provider in a prompt only under the name voice; the other two have no use for it.
    private(set) var userName: String {
        didSet { writeJSON(userName, Key.userName) }
    }

    func setUserName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard userName != trimmed else { return }
        userName = trimmed
    }

    // "It's been a while" cards on Today. On by default; the one surface that can name a person
    // the user hasn't written about, so it gets its own switch as well as a per-person mute on
    // the Entity itself.
    var resurfacingEnabled: Bool {
        didSet { write(resurfacingEnabled, Key.resurfacingEnabled, logged: .bool(resurfacingEnabled)) }
    }

    // One notification a day. Off until the user turns it on, which is also when iOS asks.
    var reminderEnabled: Bool {
        didSet { write(reminderEnabled, Key.reminderEnabled, logged: .bool(reminderEnabled)) }
    }

    // When it comes, as minutes after midnight in the user's own time zone.
    var reminderMinutes: Int {
        didSet { write(reminderMinutes, Key.reminderMinutes, logged: .int(reminderMinutes)) }
    }

    // Which Today cards were dismissed, and on what day. Written as JSON so the card keys, which
    // can name an entity or a loose end, never reach the diagnostics log.
    private(set) var todayDismissal: TodayDismissal {
        didSet { writeJSON(todayDismissal, Key.todayDismissed) }
    }

    func dismissedTodayCards(on day: String) -> Set<String> {
        todayDismissal.keys(on: day)
    }

    func dismissTodayCard(_ key: String, on day: String) {
        var updated = todayDismissal
        updated.dismiss(key, on: day)
        guard updated != todayDismissal else { return }
        todayDismissal = updated
    }

    // Which Reflect items were dismissed, keyed by period rather than day, and never thrown away:
    // a week you looked back on stays looked back on.
    private(set) var reflectDismissal: ReflectDismissal {
        didSet { writeJSON(reflectDismissal, Key.reflectDismissed) }
    }

    func dismissedReflectItems(for periodKey: String) -> Set<String> {
        reflectDismissal.itemIDs(for: periodKey)
    }

    func dismissReflectItem(_ itemID: String, for periodKey: String) {
        var updated = reflectDismissal
        updated.dismiss(itemID, for: periodKey)
        guard updated != reflectDismissal else { return }
        reflectDismissal = updated
    }

    var promptVoice: PromptVoice {
        PromptVoice(voice: journalVoice, name: userName)
    }

    func name(of area: LifeArea) -> String {
        let custom = lifeAreaNames[area.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? area.defaultName : custom
    }

    func rename(_ area: LifeArea, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty || trimmed == area.defaultName ? nil : String(trimmed.prefix(30))
        guard lifeAreaNames[area.rawValue] != stored else { return }
        lifeAreaNames[area.rawValue] = stored
    }

    func isHidden(_ area: LifeArea) -> Bool {
        hiddenLifeAreas.contains(area.rawValue)
    }

    func setHidden(_ area: LifeArea, _ hidden: Bool) {
        if hidden { hiddenLifeAreas.insert(area.rawValue) } else { hiddenLifeAreas.remove(area.rawValue) }
    }

    var visibleLifeAreas: [LifeArea] {
        LifeArea.allCases.filter { !isHidden($0) }
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
        appLockEnabled = bool(Key.appLockEnabled, false)
        welcomeSeen = bool(Key.welcomeSeen, false)
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
        storedInsightsGenerator = string(Key.insightsGenerator).flatMap(InsightsGenerator.init(rawValue:))
        storedAskGenerator = string(Key.askGenerator).flatMap(AskGenerator.init(rawValue:))
        askGeneratorChosenByUser = bool(Key.askGeneratorChosenByUser, false)
        insightsTrigger = string(Key.insightsTrigger).flatMap(InsightsTrigger.init(rawValue:)) ?? .automatic
        insightSummary = bool(Key.insightSummary, true)
        insightMoods = bool(Key.insightMoods, true)
        insightLifeAreas = bool(Key.insightLifeAreas, true)
        insightTags = bool(Key.insightTags, true)
        insightMentions = bool(Key.insightMentions, true)
        insightLooseEnds = bool(Key.insightLooseEnds, true)
        insightCleanedText = bool(Key.insightCleanedText, true)
        autoApplyCleanedText = bool(Key.autoApplyCleanedText, false)
        suggestEntryDates = bool(Key.suggestEntryDates, true)
        autoApplySuggestedEntryDate = bool(Key.autoApplySuggestedEntryDate, false)
        customInsightPrompts = json(Key.customInsightPrompts, [])
        lifeAreaNames = json(Key.lifeAreaNames, [:])
        hiddenLifeAreas = json(Key.hiddenLifeAreas, [])
        journalVoice = string(Key.journalVoice).flatMap(JournalVoice.init(rawValue:)) ?? .first
        appearance = string(Key.appearance).flatMap(AppearancePreference.init(rawValue:)) ?? .system
        userName = json(Key.userName, "")
        resurfacingEnabled = bool(Key.resurfacingEnabled, true)
        reminderEnabled = bool(Key.reminderEnabled, false)
        reminderMinutes = store.object(forKey: Key.reminderMinutes) as? Int ?? ReminderPlan.defaultMinutes
        todayDismissal = json(Key.todayDismissed, TodayDismissal())
        reflectDismissal = json(Key.reflectDismissed, ReflectDismissal())
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
