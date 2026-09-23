import SwiftUI

// The AI section of the Settings root, plus the two screens it opens. AI used to be a door into a
// subsystem; it is a section like any other now, and the only things behind it are the key and what
// AI actually does with it.
struct AISettingsSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var askingConsent = false

    // Off goes straight through; on asks first, and only Allow turns it on.
    private var useAI: Binding<Bool> {
        Binding {
            settings.aiEnabled
        } set: { on in
            if on { askingConsent = true } else { settings.aiEnabled = false }
        }
    }

    var body: some View {
        Section {
            Toggle("Use AI", isOn: useAI)
                .accessibilityIdentifier("aiEnabledToggle")
                .aiConsent(isPresented: $askingConsent)

            NavigationLink {
                AIKeyView()
            } label: {
                LabeledContent("OpenAI key", value: keySummary)
            }
            .accessibilityIdentifier("aiKeyLink")

            NavigationLink {
                AIFeaturesView()
            } label: {
                LabeledContent("What AI does", value: settings.aiEnabled ? "On" : "Off")
            }
            .accessibilityIdentifier("aiFeaturesLink")
            // Unchanged from the old AI screen: on-device titles keep this live with AI off,
            // because they need no key and send nothing anywhere.
            .disabled(!settings.aiEnabled && settings.titleGenerator != .onDevice && settings.insightsGenerator != .onDevice)
        } header: {
            Text("AI")
        } footer: {
            Text("When AI is on, recordings, journal pages, and entry text are sent to OpenAI for transcription, titles, and insights. Opening a person, place, or project in your journal sends the sentences that mention it, to draft a short description.")
        }
    }

    private var keySummary: String {
        guard let account = accounts.openAIAccount, accounts.hasKey(for: account) else { return "Not set" }
        return "Saved"
    }
}

// The key, and only the key. It was half of the old AI screen, which made that screen read as much
// about credentials as about what the app does with them.
struct AIKeyView: View {
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var keyDraft = ""
    @State private var replacingKey = false
    @State private var status: ConnectionStatus = .idle
    @State private var saveError: String?
    @State private var askingConsent = false
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum ConnectionStatus: Equatable {
        case idle
        case testing
        case connected(Int)
        case failed(String)
    }

    @State private var undo = UndoQueue()

    var body: some View {
        Form {
            Section {
                if let account = accounts.openAIAccount, accounts.hasKey(for: account), !replacingKey, undo.pending == nil {
                    LabeledContent("API key", value: "Saved")
                    Button("Replace key") { replacingKey = true }
                    // A key often lives nowhere else once it's pasted here, so removing it waits
                    // for Undo's window like any other delete.
                    Button("Remove key", role: .destructive) {
                        undo.schedule([account.id], message: "Key removed") {
                            try? accounts.remove(account)
                            status = .idle
                        }
                    }
                    .accessibilityIdentifier("removeKeyButton")
                } else {
                    SecureField("sk-...", text: $keyDraft)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("openAIKeyField")
                    Button("Save key") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Link("Get a key at platform.openai.com", destination: AIConsent.keyURL)
                        .accessibilityIdentifier("getOpenAIKeyLink")
                }
                if let saveError {
                    Text(saveError).foregroundStyle(.orange)
                }
                if undo.pending == nil, accounts.openAIAccount.map(accounts.hasKey(for:)) == true {
                    Button("Test connection") { Task { await test() } }
                        .disabled(status == .testing)
                    statusView
                }
            } header: {
                Text("OpenAI")
            } footer: {
                Text("Your key is stored in this iPhone's Keychain. OpenAI bills you for what you use. Saving it asks before turning AI on.")
            }
        }
        .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: replacingKey)
        .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: status)
        .paperBackground()
        .undoPill(undo)
        .aiConsent(isPresented: $askingConsent)
        .navigationTitle("OpenAI Key")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Fills the model pickers; without a key this does nothing.
            if accounts.availableModels.isEmpty, accounts.openAIAccount.map(accounts.hasKey(for:)) == true {
                _ = await accounts.testConnection()
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            Label { Text("Testing…") } icon: { ProgressView().controlSize(.small) }
                .foregroundStyle(.secondary)
        case .connected(let count):
            Label("Connected. \(count) models available.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private func saveKey() {
        do {
            try accounts.saveOpenAIKey(keyDraft)
            keyDraft = ""
            replacingKey = false
            saveError = nil
            // A key alone sends nothing; AI turns on only once this is answered with Allow.
            if !settings.aiEnabled { askingConsent = true }
            Task { await test() }
        } catch {
            saveError = "Couldn't save the key to Keychain."
        }
    }

    private func test() async {
        status = .testing
        switch await accounts.testConnection() {
        case .success(let models): status = .connected(models.count)
        case .failure(let error): status = .failed(error.userMessage)
        }
    }
}

// What AI does, job by job. Titles and Ask were screens holding one picker each; they are rows
// here. Speech and Insights keep their screens, because each has more to say.
struct AIFeaturesView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    private let onDeviceAvailable = FoundationModelsAvailability.isAvailable

    // nil when the model can run. Distinguishes hardware that can't run it at all from Apple
    // Intelligence just being switched off, which "This iPhone can't run it" wrongly implied.
    private var onDeviceUnavailableReason: OnDeviceModelError.Reason? {
        guard !onDeviceAvailable, case .unavailable(let reason) = FoundationModelsAvailability.unavailableReason else { return nil }
        return reason
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                NavigationLink { SpeechSettingsView() } label: {
                    LabeledContent("Speech to text", value: SpeechEngineLabel.short(settings.speechEngine))
                }
                .accessibilityIdentifier("speechSettingsLink")
                NavigationLink { InsightsSettingsView() } label: {
                    LabeledContent("Insights", value: settings.insightsTrigger == .automatic ? "Automatic" : "When I ask")
                }
                .accessibilityIdentifier("insightsSettingsLink")
            }

            Section {
                Picker("Write titles with", selection: $settings.titleGenerator) {
                    Text("Nothing").tag(TitleGenerator.off)
                    Text("This iPhone").tag(TitleGenerator.onDevice)
                    Text("OpenAI").tag(TitleGenerator.openAI)
                }
                .accessibilityIdentifier("titleGeneratorPicker")
            } header: {
                Text("Titles")
            } footer: {
                Text(titleFooter)
            }

            Section {
                Picker("Read entries with", selection: $settings.insightsGenerator) {
                    Text("Nothing").tag(InsightsGenerator.off)
                    if onDeviceAvailable || settings.insightsGenerator == .onDevice {
                        Text("This iPhone").tag(InsightsGenerator.onDevice)
                    }
                    Text("OpenAI").tag(InsightsGenerator.openAI)
                }
                .accessibilityIdentifier("insightsGeneratorPicker")
            } header: {
                Text("Insights")
            } footer: {
                Text(insightsFooter)
            }

            Section {
                Picker("Answer with", selection: $settings.askGenerator) {
                    Text("Nothing").tag(AskGenerator.off)
                    if onDeviceAvailable || settings.askGenerator == .onDevice {
                        Text("This iPhone").tag(AskGenerator.onDevice)
                    }
                    Text("OpenAI").tag(AskGenerator.openAI)
                }
                .accessibilityIdentifier("askGeneratorPicker")
            } header: {
                Text("Ask")
            } footer: {
                Text(askFooter)
            }

            Section {
                NavigationLink { AdvancedAISettingsView() } label: {
                    Text("Advanced")
                }
                .accessibilityIdentifier("advancedAISettingsLink")
            } footer: {
                Text("Models, what happens when OpenAI fails, and your own insight prompts.")
            }
        }
        .paperBackground()
        .navigationTitle("What AI Does")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var titleFooter: String {
        switch settings.titleGenerator {
        case .off:
            "Entries show the first words of their text until you type a title."
        case .onDevice:
            switch onDeviceUnavailableReason {
            case nil:
                "Titles are written by Apple's on-device model. No key needed, and it works offline."
            case .appleIntelligenceNotEnabled:
                "Turn on Apple Intelligence in Settings to write titles on this iPhone, or choose OpenAI."
            case .modelNotReady:
                "Apple's on-device model is still downloading, so titles won't be written yet. Choose OpenAI, or type your own titles until it's ready."
            case .deviceNotEligible, .unknown:
                "This iPhone can't run Apple's on-device model, so titles won't be written. Choose OpenAI, or type your own titles."
            }
        case .openAI:
            settings.aiEnabled && accounts.openAIAccount != nil
                ? "Titles are written by OpenAI, using your key."
                : "Turn on AI and save a key to write titles with OpenAI."
        }
    }

    private var insightsFooter: String {
        switch settings.insightsGenerator {
        case .off:
            "Entries aren't read for moods, areas, tags, names, or loose ends, so the map and Today stay empty."
        case .onDevice:
            switch onDeviceUnavailableReason {
            case nil:
                "Entries are read by Apple's on-device model, so nothing leaves this iPhone. It reads the first few thousand characters of a long entry and doesn't clean up transcriptions or run your own prompts; OpenAI does both."
            case .appleIntelligenceNotEnabled:
                "Turn on Apple Intelligence in Settings to read entries on this iPhone, or choose OpenAI."
            case .modelNotReady:
                "Apple's on-device model is still downloading. Choose OpenAI, or wait for it to finish."
            case .deviceNotEligible, .unknown:
                "This iPhone can't run Apple's on-device model. Choose OpenAI."
            }
        case .openAI:
            settings.aiEnabled && accounts.openAIAccount != nil
                ? "Entries are read by OpenAI, using your key."
                : "Turn on AI and save a key to read entries with OpenAI."
        }
    }

    private var askFooter: String {
        switch settings.askGenerator {
        case .off:
            "Searching your journal still works. Nothing is sent anywhere."
        case .onDevice:
            switch onDeviceUnavailableReason {
            case nil:
                "Questions are answered by Apple's on-device model, so nothing leaves this iPhone. It reads less of your journal at once than OpenAI can, and once you save a key Mindlore moves questions to OpenAI unless you pick here yourself."
            case .appleIntelligenceNotEnabled:
                "Turn on Apple Intelligence in Settings to answer questions on this iPhone, or choose OpenAI."
            case .modelNotReady:
                "Apple's on-device model is still downloading. Choose OpenAI, or turn Ask off until it's ready."
            case .deviceNotEligible, .unknown:
                "This iPhone can't run Apple's on-device model. Choose OpenAI, or turn Ask off and keep searching."
            }
        case .openAI:
            settings.aiEnabled && accounts.openAIAccount != nil
                ? "The entries a question needs are sent to OpenAI with the question, and every answer says what went out."
                : "Turn on AI and save a key to answer questions with OpenAI."
        }
    }
}
