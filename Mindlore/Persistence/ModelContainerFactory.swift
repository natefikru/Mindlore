import Foundation
import SwiftData

enum StoreLocation: Equatable {
    case `default`
    case inMemory
    case file(URL)

    static let uiTestingArgument = "-uiTesting"
    static let uiTestStorePathKey = "UITEST_STORE_PATH"
    static let xcTestConfigurationKey = "XCTestConfigurationFilePath"

    static func resolve(arguments: [String], environment: [String: String]) -> StoreLocation {
        if arguments.contains(uiTestingArgument), let path = environment[uiTestStorePathKey] {
            return .file(URL(fileURLWithPath: path))
        }
        if environment[xcTestConfigurationKey] != nil {
            return .inMemory
        }
        return .default
    }
}

enum ModelContainerFactory {
    static let schema = Schema([Entry.self])

    static func make(_ location: StoreLocation, cloudKitContainerID: String? = AppConfig.cloudKitContainerID) throws -> ModelContainer {
        let configuration: ModelConfiguration
        switch location {
        case .default:
            let database: ModelConfiguration.CloudKitDatabase = cloudKitContainerID.map { .private($0) } ?? .none
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: database)
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .file(let url):
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
