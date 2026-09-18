import Foundation
import Testing
@testable import Mindlore

struct PromptVoiceTests {
    @Test func firstPersonIsTheDefault() {
        #expect(PromptVoice.default.subject == "I")
        #expect(PromptVoice.default.possessive == "my")
        #expect(PromptVoice.default.instruction.contains("first person"))
    }

    @Test func secondPersonWritesAsYou() {
        let voice = PromptVoice(voice: .second, name: "")
        #expect(voice.subject == "you")
        #expect(voice.possessive == "your")
        #expect(voice.instruction.contains("second person"))
    }

    @Test func theNameVoiceUsesTheName() {
        let voice = PromptVoice(voice: .name, name: "Nate")
        #expect(voice.subject == "Nate")
        #expect(voice.possessive == "Nate's")
        #expect(voice.instruction == "Write about the author by name, as Nate.")
    }

    // Telling the model to write "as ." is worse than falling back.
    @Test func theNameVoiceWithoutANameFallsBackToFirstPerson() {
        for name in ["", "   ", "\n"] {
            let voice = PromptVoice(voice: .name, name: name)
            #expect(voice.subject == "I", "\(name.debugDescription) should fall back")
            #expect(voice.instruction.contains("first person"))
        }
    }

    @Test func theNameIsTrimmed() {
        let voice = PromptVoice(voice: .name, name: "  Nate  ")
        #expect(voice.subject == "Nate")
        #expect(voice.instruction.contains("as Nate."))
    }

    @Test func everyVoiceHasASample() {
        for voice in JournalVoice.allCases {
            #expect(!voice.sample.isEmpty)
            #expect(!voice.settingsName.isEmpty)
        }
    }
}

@MainActor
struct JournalVoiceSettingsTests {
    private func store(_ values: [String: Any] = [:]) -> SettingsStore {
        let backing = FakeKeyValueStore()
        backing.values = values
        return SettingsStore(store: backing, diagnostics: .disabled)
    }

    @Test func voiceDefaultsToFirstPersonOnAnEmptyStore() {
        let settings = store()
        #expect(settings.journalVoice == .first)
        #expect(settings.userName.isEmpty)
        #expect(settings.promptVoice.subject == "I")
    }

    @Test func aStoredVoiceIsRead() {
        let settings = store([SettingsStore.Key.journalVoice: JournalVoice.second.rawValue])
        #expect(settings.journalVoice == .second)
    }

    @Test func anUnknownStoredVoiceFallsBackToFirstPerson() {
        let settings = store([SettingsStore.Key.journalVoice: "sideways"])
        #expect(settings.journalVoice == .first)
    }

    @Test func theNameIsTrimmedAndCapped() {
        let settings = store()
        settings.setUserName("   Nate   ")
        #expect(settings.userName == "Nate")

        settings.setUserName(String(repeating: "a", count: 80))
        #expect(settings.userName.count == 40)
    }

    @Test func thePromptVoiceCombinesBothSettings() {
        let settings = store()
        settings.journalVoice = .name
        settings.setUserName("Nate")
        #expect(settings.promptVoice.instruction == "Write about the author by name, as Nate.")
    }
}
