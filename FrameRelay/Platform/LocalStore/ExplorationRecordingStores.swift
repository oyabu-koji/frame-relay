import Foundation
import CoreData
import Darwin

/// D04 candidate only. Metadata atomic replacement is not a transaction with
/// media bytes and is not proof of durability after power loss.
actor AtomicFileRecordingStore: RecordingStorePort {
    private let disk: ExplorationRecordingDisk

    init(run: ExplorationRunDirectory, mode: ExplorationStoreOpenMode) throws {
        disk = try ExplorationRecordingDisk(run: run, mode: mode, kind: .atomicFile)
    }

    func execute(_ command: RecordingStoreCommand) -> RecordingStoreResult { disk.execute(command) }
    func loadUnfinished() -> UnfinishedRecordingLoadResult { disk.loadUnfinished() }
}

/// D04 candidate using a parentless private Core Data context and SQLite store.
/// A successful save reaches its coordinator, not merely an in-memory child.
actor SQLiteRecordingStore: RecordingStorePort {
    private let disk: ExplorationRecordingDisk

    init(run: ExplorationRunDirectory, mode: ExplorationStoreOpenMode) throws {
        disk = try ExplorationRecordingDisk(run: run, mode: mode, kind: .sqlite)
    }

    func execute(_ command: RecordingStoreCommand) -> RecordingStoreResult { disk.execute(command) }
    func loadUnfinished() -> UnfinishedRecordingLoadResult { disk.loadUnfinished() }
}

/// Confined to its owning actor after initialization. The lock also serializes
/// distinct adapter instances, and each transaction reads a fresh disk snapshot.
nonisolated private final class ExplorationRecordingDisk {
    enum Kind { case atomicFile, sqlite }
    private let run: ExplorationRunDirectory
    private let file: URL
    private let lockName: String
    private let context: NSManagedObjectContext?

    init(run: ExplorationRunDirectory, mode: ExplorationStoreOpenMode, kind: Kind) throws {
        self.run = run
        let file = run.url.appendingPathComponent(kind == .atomicFile ? "recordings.json" : "recordings.sqlite")
        let lockName = kind == .atomicFile ? "recordings-file.lock" : "recordings-sqlite.lock"
        self.file = file
        self.lockName = lockName
        context = try ExplorationFileLock.withLock(run: run, name: lockName) {
            var info = stat()
            let exists = lstat(file.path, &info) == 0
            guard exists || errno == ENOENT else { throw ExplorationStorageError.inaccessible }
            switch mode {
            case .createNew: guard !exists else { throw ExplorationStorageError.alreadyExists }
            case .openExisting:
                guard exists else { throw ExplorationStorageError.inaccessible }
                try ExplorationRunDirectory.requireRegularFile(file)
            }
            switch kind {
            case .atomicFile:
                if mode == .createNew {
                    try JSONEncoder().encode(RecordingStoreDocument()).write(to: file, options: .withoutOverwriting)
                }
                _ = try RecordingStoreDocument.decode(Data(contentsOf: file))
                return nil
            case .sqlite:
                try Self.validateSQLiteSidecars(file, creating: mode == .createNew)
                let context = try Self.makeContext(file: file, mode: mode)
                try context.performAndWait {
                    do {
                        if mode == .createNew {
                            let object = NSEntityDescription.insertNewObject(forEntityName: "Document", into: context)
                            object.setValue(try JSONEncoder().encode(RecordingStoreDocument()), forKey: "payload")
                            try context.save()
                        }
                        _ = try Self.readDocument(context).document
                    } catch { context.rollback(); context.reset(); throw error }
                }
                return context
            }
        }
    }

    private static func validateSQLiteSidecars(_ file: URL, creating: Bool) throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = URL(fileURLWithPath: file.path + suffix)
            var info = stat()
            if lstat(sidecar.path, &info) == 0 {
                guard !creating else { throw ExplorationStorageError.alreadyExists }
                try ExplorationRunDirectory.requireRegularFile(sidecar)
            } else if errno != ENOENT { throw ExplorationStorageError.inaccessible }
        }
    }

    private static func makeContext(file: URL, mode: ExplorationStoreOpenMode) throws -> NSManagedObjectContext {
        let entity = NSEntityDescription()
        entity.name = "Document"; entity.managedObjectClassName = "NSManagedObject"
        let payload = NSAttributeDescription()
        payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
        entity.properties = [payload]
        let model = NSManagedObjectModel()
        model.entities = [entity]; model.versionIdentifiers = ["FrameRelay-D04-v1"]
        if mode == .openExisting {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType,
                                                                                      at: file, options: nil)
            guard model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else {
                throw ExplorationStorageError.unknownSchema
            }
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: file,
                                           options: [NSMigratePersistentStoresAutomaticallyOption: false,
                                                     NSInferMappingModelAutomaticallyOption: false])
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSErrorMergePolicy
        context.undoManager = nil
        return context
    }

    private static func readDocument(_ context: NSManagedObjectContext) throws
        -> (object: NSManagedObject, document: RecordingStoreDocument) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Document")
        request.fetchLimit = 2
        request.shouldRefreshRefetchedObjects = true
        let objects = try context.fetch(request)
        guard objects.count == 1, let object = objects.first, let data = object.value(forKey: "payload") as? Data else {
            throw ExplorationStorageError.corruptStore
        }
        return (object, try RecordingStoreDocument.decode(data))
    }

    private func transaction<T>(write: Bool, _ body: (inout RecordingStoreDocument) throws -> T) throws -> T {
        try ExplorationFileLock.withLock(run: run, name: lockName) {
            try ExplorationRunDirectory.requireRegularFile(file)
            if let context {
                try Self.validateSQLiteSidecars(file, creating: false)
                return try context.performAndWait {
                    context.reset()
                    do {
                        var row = try Self.readDocument(context)
                        let value = try body(&row.document)
                        if write {
                            row.object.setValue(try JSONEncoder().encode(row.document), forKey: "payload")
                            try context.save()
                        }
                        return value
                    } catch { context.rollback(); context.reset(); throw error }
                }
            }
            var document = try RecordingStoreDocument.decode(Data(contentsOf: file))
            let value = try body(&document)
            if write { try JSONEncoder().encode(document).write(to: file, options: .atomic) }
            return value
        }
    }

    func execute(_ command: RecordingStoreCommand) -> RecordingStoreResult {
        let token: CaptureCommandToken
        switch command {
        case .commitIntent(let value, _, _), .commitResult(let value, _, _): token = value
        }
        do { return .committed(try transaction(write: true) { try $0.apply(command) }) }
        catch let error as CaptureContractError { return .rejected(token, error) }
        catch { return .unavailable(token, .adapterFailure(code: "store-commit-unavailable")) }
    }

    func loadUnfinished() -> UnfinishedRecordingLoadResult {
        do { return .loaded(try transaction(write: false) { $0.unfinished }) }
        catch ExplorationStorageError.unknownSchema { return .unrecognizedSchema }
        catch ExplorationStorageError.corruptStore { return .corruptStore }
        catch { return .unavailable(.resourceUnavailable) }
    }
}
