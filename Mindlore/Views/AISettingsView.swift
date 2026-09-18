import SwiftUI

struct AISettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var keyDraft = ""
    @State private var replacingKey = false
    @State private var status: ConnectionStatus = .idle
    @State private var saveError: String?

    enum ConnectionStatus: Equatable {
        case idle
        case testing
        case connected(Int)
        case failed(String)
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Use AI", isOn: $settings.aiEnabled)
                    .accessibilityIdentifier("aiEnabledToggle")
            } footer: {
                Text("When AI is on, recordings, journal pages, and entry text are sent to your AI provider for transcription, titles, and insights. Opening a person, place, or project in your journal sends the sentences that mention it, to draft a short description.")
            }

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

            Section {
                NavigationLink { SpeechSettingsView() } label: {
                    LabeledContent("Speech to text", value: SpeechEngineLabel.short(settings.speechEngine))
                }
                .accessibilityIdentifier("speechSettingsLink")
                NavigationLink { PageSettingsView() } label: {
                    LabeledContent("Journal pages", value: settings.pageModel)
                }
                .accessibilityIdentifier("pageSettingsLink")
                NavigationLink { TitleSettingsView() } label: {
                    LabeledContent("Titles", value: titleSummary)
                }
                .accessibilityIdentifier("titleSettingsLink")
                NavigationLink { AskSettingsView() } label: {
                    LabeledContent("Ask", value: askSummary)
                }
                .accessibilityIdentifier("askSettingsLink")
                NavigationLink { InsightsSettingsView() } label: {
                    LabeledContent("Insights", value: settings.insightsTrigger == .automatic ? "Automatic" : "When I ask")
                }
                .accessibilityIdentifier("insightsSettingsLink")
            } header: {
                Text("What AI does")
            }
            .disabled(!settings.aiEnabled && settings.titleGenerator != .onDevice)
        }
        .navigationTitle("AI")
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

    private var askSummary: String {
        switch settings.askGenerator {
        case .off: "Off"
        case .onDevice: "This iPhone"
        case .openAI: "OpenAI"
        }
    }

    private var titleSummary: String {
        switch settings.titleGenerator {
        case .off: "Off"
        case .onDevice: "This iPhone"
        case .openAI: "OpenAI"
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
