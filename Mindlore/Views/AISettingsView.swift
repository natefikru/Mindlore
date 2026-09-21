import SwiftUI

// The AI section of the Settings root, plus the two screens it opens. AI used to be a door into a
// subsystem; it is a section like any other now, and the only things behind it are the key and what
// AI actually does with it.
struct AISettingsSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts

    var body: some View {
        @Bindable var settings = settings

        Section {
            Toggle("Use AI", isOn: $settings.aiEnabled)
                .accessibilityIdentifier("aiEnabledToggle")

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
            .disabled(!settings.aiEnabled && settings.titleGenerator != .onDevice)
        } header: {
            Text("AI")
        } footer: {
            Text("When AI is on, recordings, journal pages, and entry text are sent to your AI provider for transcription, titles, and insights. Opening a person, place, or project in your journal sends the sentences that mention it, to draft a short description.")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum ConnectionStatus: Equatable {
        case idle
        case testing
        case connected(Int)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                if let account = accounts.openAIAccount, accounts.hasKey(for: account), !replacingKey {
                    LabeledContent("API key", value: "Saved")
                    Button("Replace key") { replacingKey = true }
                    Button("Remove key", role: .destructive) {
                        try? accounts.remove(account)
                        status = .idle
                    }
                } else {
                    SecureField("sk-...", text: $keyDraft)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("openAIKeyField")
                    Button("Save key") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let saveError {
                    Text(saveError).foregroundStyle(.orange)
                }
                if accounts.openAIAccount.map(accounts.hasKey(for:)) == true {
                    Button("Test connection") { Task { await test() } }
                        .disabled(status == .testing)
                    statusView
                }
            } header: {
                Text("OpenAI")
            } footer: {
                Text("Your key is stored in this iPhone's Keychain.")
            }
        }
        .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: replacingKey)
        .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: status)
        .paperBackground()
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
            onDeviceAvailable
                ? "Titles are written by Apple's on-device model. No key needed, and it works offline."
                : "This iPhone can't run Apple's on-device model, so titles won't be written. Turn on Apple Intelligence in Settings, choose OpenAI, or type your own titles."
        case .openAI:
            settings.aiEnabled && accounts.openAIAccount != nil
                ? "Titles are written by OpenAI, using your key."
                : "Turn on AI and save a key to write titles with OpenAI."
        }
    }

    private var askFooter: String {
        switch settings.askGenerator {
        case .off:
            "Searching your journal still works. Nothing is sent anywhere."
        case .onDevice:
            onDeviceAvailable
                ? "Questions are answered by Apple's on-device model, so nothing leaves this iPhone. It reads less of your journal at once than OpenAI can, and once you save a key Mindlore moves questions to OpenAI unless you pick here yourself."
                : "This iPhone can't run Apple's on-device model. Choose OpenAI, or turn Ask off and keep searching."
        case .openAI:
            settings.aiEnabled && accounts.openAIAccount != nil
                ? "The entries a question needs are sent to OpenAI with the question, and every answer says what went out."
                : "Turn on AI and save a key to answer questions with OpenAI."
        }
    }
}
