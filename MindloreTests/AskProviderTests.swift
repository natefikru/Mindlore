import Foundation
import Testing
@testable import Mindlore

// Where a question goes. Until the user picks, the app follows the phone: on device while that is
// all there is, OpenAI once a key is saved. A pick in the picker ends that for good.
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

    // The phone answers while it is all there is, and a saved key takes over on the next open.
    @Test func theDefaultFollowsThePhoneUntilAKeyIsSaved() {
        let (settings, _) = stores()

        #expect(settings.refreshAskGeneratorDefault(textUsable: false, onDeviceAvailable: true) == .onDevice)
        #expect(settings.refreshAskGeneratorDefault(textUsable: true, onDeviceAvailable: true) == .openAI)
        #expect(settings.askGenerator == .openAI)
        #expect(settings.hasChosenAskGenerator == false, "the app decided this, not the user")

        // And back, if the key goes away again.
        #expect(settings.refreshAskGeneratorDefault(textUsable: false, onDeviceAvailable: true) == .onDevice)
    }

    @Test func withNeitherProviderThereIsOnlySearch() {
        let (settings, _) = stores()

        #expect(settings.refreshAskGeneratorDefault(textUsable: false, onDeviceAvailable: false) == .off)
    }

    // Once the user picks, that is the answer. A key saved afterwards doesn't move a question
    // they deliberately kept on their phone.
    @Test func aUserChoiceEndsTheAutomaticPart() {
        let (settings, _) = stores()
        settings.refreshAskGeneratorDefault(textUsable: false, onDeviceAvailable: true)
        #expect(settings.hasChosenAskGenerator == false)

        settings.askGenerator = .onDevice
        #expect(settings.hasChosenAskGenerator)

        #expect(settings.refreshAskGeneratorDefault(textUsable: true, onDeviceAvailable: true) == .onDevice)
    }

    @Test func aUserChoiceSurvivesARelaunch() {
        let store = FakeKeyValueStore()
        SettingsStore(store: store, diagnostics: .disabled).askGenerator = .onDevice

        let relaunched = SettingsStore(store: store, diagnostics: .disabled)
        #expect(relaunched.hasChosenAskGenerator)
        #expect(relaunched.refreshAskGeneratorDefault(textUsable: true, onDeviceAvailable: true) == .onDevice)
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
