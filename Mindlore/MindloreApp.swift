//
//  MindloreApp.swift
//  Mindlore
//
//  Created by Nate Fikru on 9/15/26.
//

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
        let defaults = testStoreName.flatMap { UserDefaults(suiteName: "uitest-\($0)") } ?? .standard
        let secrets = KeychainSecretStore(service: testStoreName.map { "\(KeychainSecretStore.productionService).uitest.\($0)" } ?? KeychainSecretStore.productionService)
        let http: any HTTPClient = uiTesting && arguments.contains(UITestingHTTPClient.launchArgument) ? UITestingHTTPClient() : URLSessionHTTPClient()
        let settingsStore = SettingsStore(store: defaults, onDeviceTitlesAvailable: { !uiTesting && FoundationModelsAvailability.isAvailable })
        settingsStore.recordAutomationStartIfNeeded()
        _settings = State(initialValue: settingsStore)
        _accounts = State(initialValue: ProviderAccountStore(settings: settingsStore, secrets: secrets, http: http))

        // Runs before any UI exists, so no recording can be in progress yet.
        let recovered = (try? RecordingsDirectory.standard.recoverInterruptedRecordings()) ?? []
        if !recovered.isEmpty {
            diagnostics.record("recovery.moved", ["count": .int(recovered.count), "files": .string(recovered.map(\.lastPathComponent).joined(separator: ","))])
        }
        let location = StoreLocation.resolve(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
        container = Result { try ModelContainerFactory.make(location) }
        switch container {
        case .success(let opened):
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
            case .failure(let error):
                StoreErrorView(error: error)
            }
        }
    }
}
