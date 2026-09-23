#if DEBUG
import CoreData
import Foundation
import SwiftData

// Writes the whole model to the CloudKit container's Development schema, every field of every
// record type, through Core Data's `initializeCloudKitSchema`. Without it Development only learns a
// field once a record carrying it syncs, so a field no record has set yet (a merge, a due date, a
// formatted entry) is missing, and a schema deployed to Production from there rejects every record
// that later sets it. Run once on a device signed in to iCloud before deploying the schema:
// `scripts/device/launch.sh schema -- -initializeCloudKitSchema`. It uses its own throwaway store,
// never the journal's, and Apple's pattern for SwiftData: the same model as a Core Data model,
// loaded into an NSPersistentCloudKitContainer.
enum CloudKitSchemaInitializer {
    static let launchArgument = "-initializeCloudKitSchema"

    static func runIfRequested(arguments: [String], containerID: String?, diagnostics: DiagnosticsLog) {
        guard arguments.contains(launchArgument) else { return }
        guard let containerID else {
            diagnostics.record("sync.schemaInitialized", ["ok": .bool(false), "reason": .string("noContainer")])
            return
        }
        let started = Date.now
        do {
            try initialize(containerID: containerID)
            diagnostics.record("sync.schemaInitialized", ["ok": .bool(true), "milliseconds": .int(Int(Date.now.timeIntervalSince(started) * 1000))])
        } catch {
            diagnostics.record("sync.schemaInitialized", ["ok": .bool(false), "error": .errorCode(error)])
        }
    }

    private static func initialize(containerID: String) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: ModelContainerFactory.modelTypes) else {
            throw CocoaError(.coreData)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cloudkit-schema", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let description = NSPersistentStoreDescription(url: folder.appendingPathComponent("schema.store"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "MindloreSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        try container.initializeCloudKitSchema()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: folder)
    }
}
#endif
