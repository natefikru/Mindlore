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
                Text("When AI is on, recordings, journal pages, and entry text are sent to your AI provider for transcription, titles, and insights.")
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
        }
        .navigationTitle("AI")
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
        switch await accounts.testConnection(http: URLSessionHTTPClient()) {
        case .success(let models): status = .connected(models.count)
        case .failure(let error): status = .failed(error.userMessage)
        }
    }
}
