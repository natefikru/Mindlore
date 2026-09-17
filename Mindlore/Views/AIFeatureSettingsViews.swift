import SwiftUI

// Picks a model: the provider's list when it has been loaded, and always a free-text field so a
// model Mindlore doesn't know about can still be used.
struct ModelField: View {
    let title: String
    let capability: AICapability
    @Binding var model: String
    @Environment(ProviderAccountStore.self) private var accounts

    private var options: [String] {
        var options = ModelCatalog.models(for: capability, in: accounts.availableModels)
        if !model.isEmpty && !options.contains(model) {
            options.insert(model, at: 0)
        }
        return options
    }

    var body: some View {
        Group {
            if options.count > 1 {
                Picker(title, selection: $model) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .accessibilityIdentifier("\(capability.rawValue)ModelPicker")
            } else {
                LabeledContent(title) {
                    TextField("Model", text: $model)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("\(capability.rawValue)ModelField")
                }
            }
        }
    }
}

struct SpeechSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Transcribe with", selection: $settings.speechEngine) {
                    Text("Live").tag(SpeechEngine.onDeviceLive)
                    Text("This iPhone").tag(SpeechEngine.onDevice)
                    Text("OpenAI").tag(SpeechEngine.cloud)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("speechEnginePicker")
            } footer: {
                Text(Self.engineExplanation(settings.speechEngine))
            }

            if settings.speechEngine == .cloud {
                Section {
                    ModelField(title: "Model", capability: .speech, model: $settings.speechModel)
                    Toggle("Use this iPhone when OpenAI fails", isOn: $settings.fallBackToOnDevice)
                        .accessibilityIdentifier("speechFallbackToggle")
                } footer: {
                    Text("With this off, a recording that OpenAI can't transcribe waits for you to tap Retry.")
                }
                .disabled(!AIServices.pagesUsable(settings: settings, accounts: accounts) && !settings.aiEnabled)
            }
        }
        .navigationTitle("Speech to Text")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension SpeechSettingsView {
    static func engineExplanation(_ engine: SpeechEngine) -> String {
        switch engine {
        case .onDeviceLive:
            "Text appears as you talk, written by this iPhone and never sent anywhere. On a recording this iPhone can't handle live, the text arrives right after you finish instead."
        case .onDevice:
            "Text arrives right after you finish recording, written by this iPhone and never sent anywhere."
        case .cloud:
            "Recordings are sent to OpenAI once you finish, and the text comes back after that. Recordings made before you turned AI on stay on this iPhone unless you tap Retry."
        }
    }
}

struct PageSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                ModelField(title: "Model", capability: .pages, model: $settings.pageModel)
            } footer: {
                Text("Photographed journal pages are sent to this model, one page at a time. You review the text before anything else runs on it.")
            }
        }
        .navigationTitle("Journal Pages")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TitleSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    private let onDeviceAvailable = FoundationModelsAvailability.isAvailable

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Write titles with", selection: $settings.titleGenerator) {
                    Text("Nothing").tag(TitleGenerator.off)
                    Text("This iPhone").tag(TitleGenerator.onDevice)
                    Text("OpenAI").tag(TitleGenerator.openAI)
                }
                .accessibilityIdentifier("titleGeneratorPicker")
            } footer: {
                Text(footer)
            }

            if settings.titleGenerator == .openAI {
                Section {
                    ModelField(title: "Model", capability: .text, model: $settings.textModel)
                } footer: {
                    Text("Titles use the same model as insights.")
                }
            }
        }
        .navigationTitle("Titles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footer: String {
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
}

struct InsightsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Generate insights", selection: $settings.insightsTrigger) {
                    Text("Automatically").tag(InsightsTrigger.automatic)
                    Text("Only when I ask").tag(InsightsTrigger.manual)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("insightsTriggerPicker")
            } footer: {
                Text(settings.insightsTrigger == .automatic
                     ? "Each entry is analyzed once: when you tap Done, when a recording's text arrives, or when you approve photographed pages. Run AI covers everything after that."
                     : "Nothing is analyzed until you tap Run AI on an entry.")
            }

            Section("What to generate") {
                Toggle("Summary", isOn: $settings.insightSummary).accessibilityIdentifier("insightSummaryToggle")
                Toggle("Moods", isOn: $settings.insightMoods).accessibilityIdentifier("insightMoodsToggle")
                Toggle("Life areas", isOn: $settings.insightLifeAreas).accessibilityIdentifier("insightLifeAreasToggle")
                if settings.insightLifeAreas {
                    NavigationLink("Edit life areas") { LifeAreasSettingsView() }
                        .accessibilityIdentifier("editLifeAreasLink")
                }
                Toggle("Tags", isOn: $settings.insightTags).accessibilityIdentifier("insightTagsToggle")
                Toggle("People and places", isOn: $settings.insightMentions).accessibilityIdentifier("insightMentionsToggle")
                Toggle("Open threads", isOn: $settings.insightOpenThreads).accessibilityIdentifier("insightOpenThreadsToggle")
            }

            Section {
                Toggle("Clean up transcriptions", isOn: $settings.insightCleanedText)
                    .accessibilityIdentifier("insightCleanedTextToggle")
                if settings.insightCleanedText {
                    Toggle("Use the cleaned-up version automatically", isOn: $settings.autoApplyCleanedText)
                        .accessibilityIdentifier("autoApplyCleanedTextToggle")
                }
            } header: {
                Text("Transcribed entries")
            } footer: {
                Text(settings.insightCleanedText
                     ? (settings.autoApplyCleanedText
                        ? "The cleaned-up text replaces a transcribed entry's text on its own. Your original is kept, and you can always revert."
                        : "The cleaned-up text is offered in the entry's insights, and replaces the text only when you tap it.")
                     : "Only transcribed entries are cleaned up, from recordings or journal pages. Your typed words are never rewritten.")
            }

            Section {
                Toggle("Suggest entry dates", isOn: $settings.suggestEntryDates)
                    .accessibilityIdentifier("suggestEntryDatesToggle")
                if settings.suggestEntryDates {
                    Toggle("Use the suggested date automatically", isOn: $settings.autoApplySuggestedEntryDate)
                        .accessibilityIdentifier("autoApplyEntryDateToggle")
                }
            } footer: {
                Text(settings.suggestEntryDates
                     ? (settings.autoApplySuggestedEntryDate
                        ? "A date found on a journal page or in a pasted entry becomes the entry's date on its own. You can still change it from the entry."
                        : "When a journal page or a pasted entry states the date it was written, Mindlore offers it as the entry's date. You confirm it.")
                     : "Entries keep the date they were added.")
            }

            Section {
                ModelField(title: "Model", capability: .text, model: $settings.textModel)
            } footer: {
                Text(accounts.openAIAccount == nil ? "Save an OpenAI key to generate insights." : "")
            }

            Section {
                NavigationLink {
                    CustomInsightsSettingsView()
                } label: {
                    LabeledContent("Custom insights", value: customSummary)
                }
                .accessibilityIdentifier("customInsightsLink")
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customSummary: String {
        let enabled = settings.customInsightPrompts.filter(\.enabled).count
        return enabled == 0 ? "None" : "\(enabled)"
    }
}

// The user's own insight prompts: each one becomes a card on every entry that's analyzed.
struct CustomInsightsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var editing: CustomInsightPrompt?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                ForEach($settings.customInsightPrompts) { $prompt in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(prompt.name.isEmpty ? "Untitled" : prompt.name)
                            Text(prompt.instructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: $prompt.enabled)
                            .labelsHidden()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = prompt }
                    .accessibilityIdentifier("customPromptRow")
                }
                .onDelete { offsets in settings.customInsightPrompts.remove(atOffsets: offsets) }
                .onMove { source, destination in settings.customInsightPrompts.move(fromOffsets: source, toOffset: destination) }
            } footer: {
                Text("Each prompt is answered for every entry that gets insights, alongside the built-in ones.")
            }

            Section {
                Button("Add prompt", systemImage: "plus") {
                    let prompt = CustomInsightPrompt(id: UUID(), name: "", instructions: "", enabled: true)
                    settings.customInsightPrompts.append(prompt)
                    editing = prompt
                }
                .accessibilityIdentifier("addCustomPromptButton")
            }
        }
        .navigationTitle("Custom Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(item: $editing) { prompt in
            CustomPromptEditor(prompt: prompt) { updated in
                guard let index = settings.customInsightPrompts.firstIndex(where: { $0.id == updated.id }) else { return }
                settings.customInsightPrompts[index] = updated
            }
        }
    }
}

private struct CustomPromptEditor: View {
    @State private var prompt: CustomInsightPrompt
    private let onSave: (CustomInsightPrompt) -> Void
    @Environment(\.dismiss) private var dismiss

    init(prompt: CustomInsightPrompt, onSave: @escaping (CustomInsightPrompt) -> Void) {
        _prompt = State(initialValue: prompt)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Gratitude", text: $prompt.name)
                        .accessibilityIdentifier("customPromptNameField")
                }
                Section {
                    TextField("What is the writer grateful for?", text: $prompt.instructions, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("customPromptInstructionsField")
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Written for the AI, about the entry. It answers with nothing when the entry gives it nothing to say.")
                }
            }
            .navigationTitle("Custom Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(prompt)
                        dismiss()
                    }
                    .disabled(prompt.name.trimmingCharacters(in: .whitespaces).isEmpty || prompt.instructions.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("saveCustomPromptButton")
                }
            }
        }
    }
}
