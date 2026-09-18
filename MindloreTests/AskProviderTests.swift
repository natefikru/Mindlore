import Foundation
import Testing
@testable import Mindlore

// Where a question goes: the setting decides, and the default is decided once, the first time
// Ask opens. A rule that kept re-deciding would move a question's destination behind the user's
// back, which is what tasks/lessons.md warns about.
@MainActor
struct AskProviderTests {
    private func stores() -> (SettingsStore, ProviderAccountStore) {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        return (settings, ProviderAccountStore(settings: settings, secrets: FakeSecretStore(), diagnostics: .disabled))
    }

    @Test func nothingIsChosenUntilAskFirstOpens() {
        let (settings, _) = stores()

        #expect(settings.hasChosenAskGenerator == false)
        #expect(settings.askGenerator == .off)
    }

    @Test func theFirstOpenPicksOpenAIWhenItCanRunAndTheOnDeviceModelOtherwise() {
        let (usable, _) = stores()
        #expect(usable.chooseAskGeneratorIfNeeded(textUsable: true, onDeviceAvailable: false) == .openAI)

        let (local, _) = stores()
        #expect(local.chooseAskGeneratorIfNeeded(textUsable: false, onDeviceAvailable: true) == .onDevice)

        let (neither, _) = stores()
        #expect(neither.chooseAskGeneratorIfNeeded(textUsable: false, onDeviceAvailable: false) == .off)
    }

    // Saving a key later must not move a question that the user left on this iPhone.
    @Test func aChoiceOnceMadeIsNeverRedecided() {
        let (settings, _) = stores()
        settings.chooseAskGeneratorIfNeeded(textUsable: false, onDeviceAvailable: true)

        #expect(settings.chooseAskGeneratorIfNeeded(textUsable: true, onDeviceAvailable: true) == .onDevice)
        #expect(settings.hasChosenAskGenerator)

        settings.askGenerator = .openAI
        #expect(settings.chooseAskGeneratorIfNeeded(textUsable: true, onDeviceAvailable: true) == .openAI)
    }

    @Test func theChoiceSurvivesARelaunch() {
        let store = FakeKeyValueStore()
        SettingsStore(store: store, diagnostics: .disabled).askGenerator = .onDevice

        let relaunched = SettingsStore(store: store, diagnostics: .disabled)
        #expect(relaunched.askGenerator == .onDevice)
        #expect(relaunched.hasChosenAskGenerator)
    }

    @Test func offMeansSearchOnly() {
        let (settings, accounts) = stores()
        settings.askGenerator = .off

        #expect(AIServices.askUsable(settings: settings, accounts: accounts) == false)
        guard case .failure(let failure) = AIServices.askGenerator(settings: settings, accounts: accounts) else {
            Issue.record("off resolved to a provider")
            return
        }
        #expect(failure.raw == "settings.off")
    }

    @Test func openAINeedsAIOnAndAKey() throws {
        let (settings, accounts) = stores()
        settings.askGenerator = .openAI

        guard case .failure(let offFailure) = AIServices.askGenerator(settings: settings, accounts: accounts) else {
            Issue.record("a question went out with AI off")
            return
        }
        #expect(offFailure.raw == "settings.aiOff")

        settings.aiEnabled = true
        guard case .failure(let keyFailure) = AIServices.askGenerator(settings: settings, accounts: accounts) else {
            Issue.record("a question went out with no key")
            return
        }
        #expect(keyFailure.raw == "ai.missingKey")

        _ = try accounts.saveOpenAIKey("sk-test")
        #expect(AIServices.askUsable(settings: settings, accounts: accounts))
        guard case .success(let provider) = AIServices.askGenerator(settings: settings, accounts: accounts) else {
            Issue.record("a saved key still didn't resolve")
            return
        }
        #expect(provider.kind == .openAI)
        #expect(provider.label == "openai:\(settings.textModel)")
    }

    // The simulator has no on-device model, so this is the unavailable branch either way it runs.
    @Test func theOnDeviceChoiceReportsWhyItCantRun() {
        let (settings, accounts) = stores()
        settings.askGenerator = .onDevice

        let resolved = AIServices.askGenerator(settings: settings, accounts: accounts)
        #expect(AIServices.askUsable(settings: settings, accounts: accounts) == FoundationModelsAvailability.isAvailable)
        switch resolved {
        case .success(let provider):
            #expect(FoundationModelsAvailability.isAvailable)
            #expect(provider.kind == .onDevice)
            #expect(provider.label == FoundationModelsTextGenerator.label)
        case .failure(let failure):
            #expect(!FoundationModelsAvailability.isAvailable)
            #expect(failure.raw.hasPrefix("device."))
        }
    }
}
