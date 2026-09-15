import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct ModelContainerFactoryTests {
    @Test func resolvesDefaultForNormalLaunch() {
        #expect(StoreLocation.resolve(arguments: ["Mindlore"], environment: [:]) == .default)
    }

    @Test func resolvesInMemoryForHostedUnitTests() {
        let environment = [StoreLocation.xcTestConfigurationKey: "/tmp/config.xctestconfiguration"]
        #expect(StoreLocation.resolve(arguments: ["Mindlore"], environment: environment) == .inMemory)
    }

    @Test func resolvesNamedFileForUITests() {
        let directory = URL(fileURLWithPath: "/tmp/support", isDirectory: true)
        let environment = [StoreLocation.uiTestStoreNameKey: "abc"]
        let location = StoreLocation.resolve(arguments: ["Mindlore", StoreLocation.uiTestingArgument], environment: environment, directory: directory)
        #expect(location == .file(directory.appendingPathComponent("uitest-abc.store")))
    }

    @Test func uiTestingArgumentWithoutStoreNameDoesNotUseAFile() {
        let location = StoreLocation.resolve(arguments: ["Mindlore", StoreLocation.uiTestingArgument], environment: [:])
        #expect(location == .default)
    }

    @Test func storeNameWithoutUITestingArgumentIsIgnored() {
        let environment = [StoreLocation.uiTestStoreNameKey: "abc"]
        #expect(StoreLocation.resolve(arguments: ["Mindlore"], environment: environment) == .default)
    }

    @Test func inMemoryStoresDoNotShareData() throws {
        let first = try ModelContainerFactory.make(.inMemory)
        first.mainContext.insert(Entry(text: "only in first"))
        try first.mainContext.save()

        let second = try ModelContainerFactory.make(.inMemory)
        #expect(try second.mainContext.fetchCount(FetchDescriptor<Entry>()) == 0)
    }

    @Test func fileStorePersistsAcrossContainers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/entries.store")
        let id = UUID()

        do {
            let writer = try ModelContainerFactory.make(.file(url))
            writer.mainContext.insert(Entry(id: id, text: "persisted"))
            try writer.mainContext.save()
        }

        let reader = try ModelContainerFactory.make(.file(url))
        let entries = try reader.mainContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.map(\.id) == [id])
        #expect(entries.first?.text == "persisted")
    }
}
