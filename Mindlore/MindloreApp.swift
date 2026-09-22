//
//  MindloreApp.swift
//  Mindlore
//
//  Created by Nate Fikru on 9/15/26.
//

import Speech
import SwiftUI
import SwiftData

@main
struct MindloreApp: App {
    private let container: Result<ModelContainer, any Error>
    @State private var settings: SettingsStore
    @State private var accounts: ProviderAccountStore

    init() {
        let diagnostics = DiagnosticsLog.shared
        let arguments = ProcessInfo.processInfo.arguments
        let info = Bundle.main.infoDictionary
        var launch: [String: DiagnosticValue] = [
            "version": .string(info?["CFBundleShortVersionString"] as? String ?? "?"),
            "build": .string(info?["CFBundleVersion"] as? String ?? "?"),
        ]
        if let index = arguments.firstIndex(of: "-diagnosticsRun"), arguments.indices.contains(index + 1) {
            launch["run"] = .string(arguments[index + 1])
        }
        diagnostics.record("app.launch", launch)

        // UI tests get their own settings and Keychain per named store, and run against whatever model
        // the simulator's host offers, so on-device titles stay off to keep them deterministic.
        let uiTesting = arguments.contains(StoreLocation.uiTestingArgument)
        let testStoreName = uiTesting ? ProcessInfo.processInfo.environment[StoreLocation.uiTestStoreNameKey] : nil
        #if DEBUG
        let demo = uiTesting ? nil : DemoJournal.request(in: arguments)
        // The generated journal keeps its own settings and Keychain entry, so AI starts off there
        // and a test run never sends made-up entries with the real key. The story journal is the
        // one the owner looks at, so it runs on the real settings and key: Reflect and Ask answer
        // it the way they would the real journal. Its entries are past the automatic pass, so
        // nothing runs AI on them unasked.
        let isolatesSettings = demo != nil && demo != .story
        #else
        let isolatesSettings = false
        #endif
        #if DEBUG
        // A UI test that dismisses something needs to start from the same place every run, and the
        // demo suite otherwise outlives the run that wrote it.
        if isolatesSettings, arguments.contains(DemoJournal.resetSettingsArgument) {
            UserDefaults.standard.removePersistentDomain(forName: DemoJournal.settingsSuiteName)
        }
        let demoDefaults = !isolatesSettings ? nil : UserDefaults(suiteName: DemoJournal.settingsSuiteName)
        #else
        let demoDefaults: UserDefaults? = nil
        #endif
        let defaults = testStoreName.flatMap { UserDefaults(suiteName: "uitest-\($0)") } ?? demoDefaults ?? .standard
        // A real key handed to a UI test run stays in memory so it never touches the Keychain; test
        // runs with the stub's key use a Keychain service named for the run, so saving a key and
        // finding it after a relaunch still works.
        let liveTestKey = ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        let secrets: any SecretStore = switch (testStoreName, liveTestKey) {
        case (nil, _) where isolatesSettings: KeychainSecretStore(service: "\(KeychainSecretStore.productionService).demo")
        case (nil, _): KeychainSecretStore()
        case (_, .some): InMemorySecretStore()
        case (.some(let name), nil): KeychainSecretStore(service: "\(KeychainSecretStore.productionService).uitest.\(name)")
        }
        let http: any HTTPClient = uiTesting && arguments.contains(UITestingHTTPClient.launchArgument) ? UITestingHTTPClient() : URLSessionHTTPClient()
        let settingsStore = SettingsStore(
            store: defaults,
            onDeviceTitlesAvailable: { !uiTesting && FoundationModelsAvailability.isAvailable },
            onDeviceSpeechAvailable: { !uiTesting && SpeechTranscriber.isAvailable }
        )
        settingsStore.recordAutomationStartIfNeeded()
        let accountStore = ProviderAccountStore(settings: settingsStore, secrets: secrets, http: http)
        // UI tests that need AI start with it on and the stub's key saved, instead of typing it each time.
        // A real key passed by the test runner (MINDLORE_OPENAI_KEY) runs against OpenAI; otherwise the stub's key.
        if uiTesting, testStoreName != nil, arguments.contains(UITestingHTTPClient.readyArgument), accountStore.openAIAccount == nil {
            try? accountStore.saveOpenAIKey(liveTestKey ?? UITestingHTTPClient.validKey)
            settingsStore.aiEnabled = true
        }
        _settings = State(initialValue: settingsStore)
        _accounts = State(initialValue: accountStore)

        // Runs before any UI exists, so no recording can be in progress yet.
        let recovered = (try? RecordingsDirectory.standard.recoverInterruptedRecordings()) ?? []
        if !recovered.isEmpty {
            diagnostics.record("recovery.moved", ["count": .int(recovered.count), "files": .string(recovered.map(\.lastPathComponent).joined(separator: ","))])
        }
        let location = StoreLocation.resolve(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
        #if DEBUG
        if let demo, case .file(let url) = location,
           arguments.contains(demo == .story ? DemoJournal.resetStoryArgument : DemoJournal.resetGeneratedArgument) {
            DemoJournal.removeStore(at: url)
        }
        #endif
        container = Result { try ModelContainerFactory.make(location) }
        switch container {
        case .success(let opened):
            #if DEBUG
            if let demo {
                do {
                    try DemoJournal.seedIfEmpty(demo, in: opened.mainContext)
                } catch {
                    diagnostics.record("demo.seedFailed", ["error": .errorCode(error)])
                }
            }
            #endif
            do {
                let repaired = try EntryDateRepair.run(in: opened.mainContext)
                if repaired > 0 {
                    diagnostics.record("store.entryDatesRepaired", ["count": .int(repaired)])
                }
            } catch {
                diagnostics.record("store.entryDateRepairFailed", ["error": .errorCode(error)])
            }
        case .failure(let error):
            diagnostics.record("store.openFailed", ["error": .errorCode(error)])
        }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                RootView(container: container, settings: settings, accounts: accounts)
                    .modelContainer(container)
                    .environment(settings)
                    .environment(accounts)
                    .preferredColorScheme(settings.appearance.colorScheme)
            case .failure(let error):
                StoreErrorView(error: error)
            }
        }
    }
}
