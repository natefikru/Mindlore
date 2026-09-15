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
    @State private var settings = SettingsStore()

    init() {
        // Runs before any UI exists, so no recording can be in progress yet.
        _ = try? RecordingsDirectory.standard.recoverInterruptedRecordings()
        let location = StoreLocation.resolve(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
        container = Result { try ModelContainerFactory.make(location) }
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                RootView(container: container)
                    .modelContainer(container)
                    .environment(settings)
            case .failure(let error):
                StoreErrorView(error: error)
            }
        }
    }
}
