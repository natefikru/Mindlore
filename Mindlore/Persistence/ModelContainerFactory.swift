import Foundation
import SwiftData

enum StoreLocation: Equatable {
    case `default`
    case inMemory
    case file(URL)

    static let uiTestingArgument = "-uiTesting"
    static let uiTestStoreNameKey = "UITEST_STORE_NAME"
    static let xcTestConfigurationKey = "XCTestConfigurationFilePath"

    static func resolve(arguments: [String], environment: [String: String], directory: URL = .applicationSupportDirectory) -> StoreLocation {
        if arguments.contains(uiTestingArgument), let name = environment[uiTestStoreNameKey] {
            return .file(directory.appendingPathComponent("uitest-\(name).store"))
        }
        if environment[xcTestConfigurationKey] != nil {
            return .inMemory
        }
        #if DEBUG
        if DemoJournal.requestedCount(in: arguments) != nil {
            return .file(directory.appendingPathComponent(DemoJournal.storeFileName))
        }
        #endif
        return .default
    }
}

enum ModelContainerFactory {
    static let schema = Schema([Entry.self, EntryPage.self, EntryInsights.self, Entity.self, EntityLink.self])

    static func make(_ location: StoreLocation, cloudKitContainerID: String? = AppConfig.cloudKitContainerID) throws -> ModelContainer {
        let configuration: ModelConfiguration
        switch location {
        case .default:
            let database: ModelConfiguration.CloudKitDatabase = cloudKitContainerID.map { .private($0) } ?? .none
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: database)
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .file(let url):
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
