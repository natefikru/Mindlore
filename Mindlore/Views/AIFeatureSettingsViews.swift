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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        }
        .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: settings.speechEngine)
        .paperBackground()
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

// Models, the cloud-failure rule, and custom prompts. Real controls, none of them daily, so they
// live one row further in rather than on the way to something else. The three model fields are the
// only way to use a model Mindlore does not ship a name for.
struct AdvancedAISettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                ModelField(title: "Speech", capability: .speech, model: $settings.speechModel)
                ModelField(title: "Journal pages", capability: .pages, model: $settings.pageModel)
                ModelField(title: "Text", capability: .text, model: $settings.textModel)
            } header: {
                Text("Models")
            } footer: {
                Text("Text covers titles and insights, which share one model. Photographed pages are sent one page at a time.")
            }

            Section {
                Toggle("Use this iPhone when OpenAI fails", isOn: $settings.fallBackToOnDevice)
                    .accessibilityIdentifier("speechFallbackToggle")
            } header: {
                Text("Recordings")
            } footer: {
                Text("With this off, a recording that OpenAI can't transcribe waits for you to tap Retry.")
            }

            Section {
                NavigationLink {
                    CustomInsightsSettingsView()
                } label: {
                    LabeledContent("Custom insights", value: customSummary)
                }
                .accessibilityIdentifier("customInsightsLink")
            } footer: {
                Text("Your own questions, answered for every entry that gets insights.")
            }
        }
        .paperBackground()
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var customSummary: String {
        let enabled = settings.customInsightPrompts.filter(\.enabled).count
        return enabled == 0 ? "None" : "\(enabled)"
    }
}

struct InsightsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            Section {
                Toggle("Summary", isOn: $settings.insightSummary)
                    .accessibilityIdentifier("insightSummaryToggle")
                    .disabled(isLastEnabled(settings.insightSummary))
                Toggle("Moods", isOn: $settings.insightMoods)
                    .accessibilityIdentifier("insightMoodsToggle")
                    .disabled(isLastEnabled(settings.insightMoods))
                Toggle("Life areas", isOn: $settings.insightLifeAreas)
                    .accessibilityIdentifier("insightLifeAreasToggle")
                    .disabled(isLastEnabled(settings.insightLifeAreas))
                Toggle("Tags", isOn: $settings.insightTags)
                    .accessibilityIdentifier("insightTagsToggle")
                    .disabled(isLastEnabled(settings.insightTags))
                Toggle("People and places", isOn: $settings.insightMentions)
                    .accessibilityIdentifier("insightMentionsToggle")
                    .disabled(isLastEnabled(settings.insightMentions))
                Toggle("Loose ends", isOn: $settings.insightLooseEnds)
                    .accessibilityIdentifier("insightLooseEndsToggle")
                    .disabled(isLastEnabled(settings.insightLooseEnds))
            } header: {
                Text("What to generate")
            } footer: {
                if onlyOneLeft {
                    Text("Insights need at least one thing to look for.")
                }
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
                        : "A date written at the top of a photographed page becomes the entry's date on its own. When a pasted entry states the date it was written, Mindlore offers it and you confirm it.")
                     : "Entries keep the date they were added.")
            }

            if accounts.openAIAccount == nil {
                Section {
                    Text("Save an OpenAI key to generate insights.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: settings.insightCleanedText)
        .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: settings.suggestEntryDates)
        .paperBackground()
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Turning the last one off asks the provider for an empty schema, which it rejects. The rule is
    // asked of `InsightSections` rather than restated here, so the screen and the request cannot
    // drift; note that cleanup and an enabled custom prompt count towards not-empty too, which is
    // why these six are free whenever either of those is on. It can only ever be an approximation:
    // what actually reaches the schema depends on the entry, and a settings screen has no entry.
    // `InsightsCoordinator.generate` holds the guard that does.
    private func isLastEnabled(_ toggle: Bool) -> Bool {
        toggle && onlyOneLeft
    }

    private var onlyOneLeft: Bool {
        let sections = AIServices.insightSections(settings)
        // Ask InsightSections whether anything outside these six would still be asked for: cleanup
        // and an enabled custom prompt each keep the schema alive on their own, and then all six
        // stay free. `suggestEntryDates` deliberately does not count, and isEmpty agrees.
        var withoutTheSix = sections
        withoutTheSix.summary = false
        withoutTheSix.moods = false
        withoutTheSix.lifeAreas = false
        withoutTheSix.tags = false
        withoutTheSix.mentions = false
        withoutTheSix.looseEnds = false
        guard withoutTheSix.isEmpty else { return false }

        let enabled = [sections.summary, sections.moods, sections.lifeAreas, sections.tags, sections.mentions, sections.looseEnds]
        return enabled.filter { $0 }.count == 1
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
        .paperBackground()
        .navigationTitle("Custom Insights")
        .navigationBarTitleDisplayMode(.inline)
        // Only with something to edit: on an empty list it was a button that did nothing.
        .toolbar {
            if !settings.customInsightPrompts.isEmpty {
                EditButton()
            }
        }
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
                    TextField("What am I grateful for?", text: $prompt.instructions, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("customPromptInstructionsField")
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Written for the AI, about the entry. It answers with nothing when the entry gives it nothing to say.")
                }
            }
            .paperBackground()
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
