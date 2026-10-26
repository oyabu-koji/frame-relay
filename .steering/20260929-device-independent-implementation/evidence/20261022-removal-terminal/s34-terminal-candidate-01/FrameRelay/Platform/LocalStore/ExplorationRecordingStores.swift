import Foundation
import CoreData
import Darwin

/// Deterministic crash-boundary simulation for disposable-store tests. A lost
/// reply is deliberately unavailable even though the disk transaction succeeded.
nonisolated enum RecordingStoreFault: Equatable, Sendable {
    case beforeDiskCommit, afterDiskCommitBeforeReply
    /// Allows real setup/reconciliation commits on the same writer epoch before
    /// interrupting only the exact operation under test.
    case beforeBackendCommit(BackendCommitIdentity)
    case afterBackendCommitBeforeReply(BackendCommitIdentity)

    func interruptsBefore(_ identity: BackendCommitIdentity?) -> Bool {
        if self == .beforeDiskCommit { return true }
        if case .beforeBackendCommit(let expected) = self { return identity == expected }
        return false
    }
    func losesReply(_ identity: BackendCommitIdentity?) -> Bool {
        if self == .afterDiskCommitBeforeReply { return true }
        if case .afterBackendCommitBeforeReply(let expected) = self { return identity == expected }
        return false
    }
}

/// D04 candidate only. Metadata atomic replacement is not a transaction with
/// media bytes and is not proof of durability after power loss.
actor AtomicFileRecordingStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    private let disk: ExplorationRecordingDisk

    init(run: ExplorationRunDirectory, mode: ExplorationStoreOpenMode,
         fault: RecordingStoreFault? = nil, supportedVerificationSchemas: Set<String> = []) throws {
        disk = try ExplorationRecordingDisk(run: run, mode: mode, kind: .atomicFile, fault: fault, supportedVerificationSchemas: supportedVerificationSchemas)
    }

    func execute(_ command: RecordingStoreCommand) -> RecordingStoreResult { disk.execute(command) }
    func loadUnfinished() -> UnfinishedRecordingLoadResult { disk.loadUnfinished() }
    func loadRecordings() -> RecordingStoreLoadResult { disk.loadRecordings() }
    func loadOriginalState() -> BackendOutcome<OriginalStoreSnapshot> { disk.loadOriginalState() }
    func loadRemovalTransportInventory(_ original: OriginalContent) -> BackendOutcome<OriginalRemovalTransportInventory> {
        disk.loadRemovalTransportInventory(original)
    }
    func commitOriginal(_ mutation: OriginalStoreMutation) -> OriginalStoreCommitResult { disk.commitOriginal(mutation) }
    func lookupOriginalCommit(_ mutation: OriginalStoreMutation) -> BackendOutcome<OriginalStoreCommitReceipt> {
        disk.lookupOriginalCommit(mutation)
    }
    func commitRemovalObservation(_ mutation: OriginalStoreMutation,
        check: @Sendable () throws -> Void) -> OriginalStoreCommitResult {
        disk.commitRemovalObservation(mutation, check: check)
    }
    func performRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        effect: @Sendable () throws -> Void) -> BackendOutcome<RemovalResolutionReceipt> {
        disk.performRemovalBoundary(boundary, effect: effect)
    }
    func establishRegistrationIdentity(expectedRevision: UInt64,
        expectedIdentity: RegistrationStoreIdentity?) async throws -> RegistrationStoreIdentity {
        try disk.establishRegistrationIdentity(expectedRevision: expectedRevision, expectedIdentity: expectedIdentity)
    }
    func load() -> BackendStoreLoadResult { disk.loadBackend() }
    func commit(_ mutation: BackendStoreMutation) -> BackendCommitResult { disk.commitBackend(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) -> BackendCommitResult { disk.lookupBackend(mutation) }
    func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        disk.lookupInvalidation(acknowledgement)
    }
}

/// Common product writer using the existing parentless Core Data/SQLite candidate.
/// A successful save reaches its coordinator, not merely an in-memory child.
actor SQLiteRecordingStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    private let disk: ExplorationRecordingDisk

    init(run: ExplorationRunDirectory, mode: ExplorationStoreOpenMode,
         fault: RecordingStoreFault? = nil, supportedVerificationSchemas: Set<String> = []) throws {
        disk = try ExplorationRecordingDisk(run: run, mode: mode, kind: .sqlite, fault: fault, supportedVerificationSchemas: supportedVerificationSchemas)
    }

    func execute(_ command: RecordingStoreCommand) -> RecordingStoreResult { disk.execute(command) }
    func loadUnfinished() -> UnfinishedRecordingLoadResult { disk.loadUnfinished() }
    func loadRecordings() -> RecordingStoreLoadResult { disk.loadRecordings() }
    func loadOriginalState() -> BackendOutcome<OriginalStoreSnapshot> { disk.loadOriginalState() }
    func loadRemovalTransportInventory(_ original: OriginalContent) -> BackendOutcome<OriginalRemovalTransportInventory> {
        disk.loadRemovalTransportInventory(original)
    }
    func commitOriginal(_ mutation: OriginalStoreMutation) -> OriginalStoreCommitResult { disk.commitOriginal(mutation) }
    func lookupOriginalCommit(_ mutation: OriginalStoreMutation) -> BackendOutcome<OriginalStoreCommitReceipt> {
        disk.lookupOriginalCommit(mutation)
    }
    func commitRemovalObservation(_ mutation: OriginalStoreMutation,
        check: @Sendable () throws -> Void) -> OriginalStoreCommitResult {
        disk.commitRemovalObservation(mutation, check: check)
    }
    func performRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        effect: @Sendable () throws -> Void) -> BackendOutcome<RemovalResolutionReceipt> {
        disk.performRemovalBoundary(boundary, effect: effect)
    }
    func establishRegistrationIdentity(expectedRevision: UInt64,
        expectedIdentity: RegistrationStoreIdentity?) async throws -> RegistrationStoreIdentity {
        try disk.establishRegistrationIdentity(expectedRevision: expectedRevision, expectedIdentity: expectedIdentity)
    }
    func load() -> BackendStoreLoadResult { disk.loadBackend() }
    func commit(_ mutation: BackendStoreMutation) -> BackendCommitResult { disk.commitBackend(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) -> BackendCommitResult { disk.lookupBackend(mutation) }
    func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        disk.lookupInvalidation(acknowledgement)
    }
}

/// Confined to its owning actor after initialization. The lock also serializes
/// distinct adapter instances, and each transaction reads a fresh disk snapshot.
nonisolated private final class ExplorationRecordingDisk {
    enum Kind { case atomicFile, sqlite }
    private let run: ExplorationRunDirectory
    private let file: URL
    private let lockName: String
    private let context: NSManagedObjectContext?
    /// Session-only guard against a live SQLite connection following an unlinked old file.
    /// This is never persisted or used as the credential/store identity.
    private var openedSQLiteFile: (device: dev_t, inode: ino_t)?
    private let fault: RecordingStoreFault?
    private let supportedVerificationSchemas: Set<String>
    private let reconciliationEpoch = ReaderReconciliationEpoch(rawValue: UUID().uuidString)

    init(run: ExplorationRunDirectory, mode: ExplorationStoreOpenMode, kind: Kind,
         fault: RecordingStoreFault?, supportedVerificationSchemas: Set<String>) throws {
        self.run = run
        self.fault = fault
        self.supportedVerificationSchemas = supportedVerificationSchemas
        let file = run.url.appendingPathComponent(kind == .atomicFile ? "recordings.json" : "recordings.sqlite")
        let lockName = kind == .atomicFile ? "recordings-file.lock" : "recordings-sqlite.lock"
        self.file = file
        self.lockName = lockName
        var openedFile: (device: dev_t, inode: ino_t)?
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
                var info = stat()
                guard lstat(file.path, &info) == 0 else { throw ExplorationStorageError.inaccessible }
                openedFile = (info.st_dev, info.st_ino)
                return context
            }
        }
        openedSQLiteFile = openedFile
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

    private func transaction<T>(write: Bool, backendIdentity: BackendCommitIdentity? = nil,
                                _ body: (inout RecordingStoreDocument) throws -> T) throws -> T {
        try ExplorationFileLock.withLock(run: run, name: lockName) {
            try ExplorationRunDirectory.requireRegularFile(file)
            if let context {
                var info = stat()
                guard let openedSQLiteFile, lstat(file.path, &info) == 0,
                      info.st_dev == openedSQLiteFile.device, info.st_ino == openedSQLiteFile.inode else {
                    throw ExplorationStorageError.inaccessible
                }
                try Self.validateSQLiteSidecars(file, creating: false)
                let interruptsBefore = fault?.interruptsBefore(backendIdentity) == true
                return try context.performAndWait {
                    context.reset()
                    do {
                        var row = try Self.readDocument(context)
                        let value = try body(&row.document)
                        if write {
                            row.object.setValue(try JSONEncoder().encode(row.document), forKey: "payload")
                            if interruptsBefore { throw ExplorationStorageError.inaccessible }
                            try context.save()
                        }
                        return value
                    } catch { context.rollback(); context.reset(); throw error }
                }
            }
            var document = try RecordingStoreDocument.decode(Data(contentsOf: file))
            let value = try body(&document)
            if write {
                let data = try JSONEncoder().encode(document)
                if fault?.interruptsBefore(backendIdentity) == true { throw ExplorationStorageError.inaccessible }
                try data.write(to: file, options: .atomic)
            }
            return value
        }
    }

    func execute(_ command: RecordingStoreCommand) -> RecordingStoreResult {
        let token: CaptureCommandToken
        switch command {
        case .commitIntent(let value, _, _), .commitResult(let value, _, _): token = value
        }
        do {
            let receipt = try transaction(write: true) { try $0.apply(command) }
            if fault == .afterDiskCommitBeforeReply { throw ExplorationStorageError.inaccessible }
            return .committed(receipt)
        }
        catch let error as CaptureContractError { return .rejected(token, error) }
        catch { return .unavailable(token, .adapterFailure(code: "store-commit-unavailable")) }
    }

    func loadUnfinished() -> UnfinishedRecordingLoadResult {
        do { return .loaded(try transaction(write: false) { $0.unfinished }) }
        catch ExplorationStorageError.unknownSchema { return .unrecognizedSchema }
        catch ExplorationStorageError.corruptStore { return .corruptStore }
        catch { return .unavailable(.resourceUnavailable) }
    }

    func loadRecordings() -> RecordingStoreLoadResult {
        do {
            return .loaded(try transaction(write: false) { document in
                RecordingStoreSnapshot(revision: document.transactionRevision,
                    recordings: document.entries.map {
                        RecordingStoreEntry(intentToken: $0.intentToken, intent: $0.intent,
                            revision: $0.revision, resultToken: $0.resultToken, result: $0.result)
                    })
            })
        } catch ExplorationStorageError.unknownSchema { return .unrecognizedSchema }
        catch ExplorationStorageError.corruptStore { return .corruptStore }
        catch { return .unavailable(.resourceUnavailable) }
    }

    func loadOriginalState() -> BackendOutcome<OriginalStoreSnapshot> {
        do {
            return .succeeded(try transaction(write: false) {
                let projection = try $0.replayStore()
                return .init(revision: $0.transactionRevision, originals: projection.originals.compactMap(\.localProjection),
                             logicalOriginals: projection.originals, reconciliationEpoch: reconciliationEpoch,
                             removalBatches: projection.removalBatches)
            })
        } catch ExplorationStorageError.unknownSchema { return .failed(.unknownSchema) }
        catch ExplorationStorageError.corruptStore { return .failed(.corruptStore) }
        catch { return .failed(.inaccessible) }
    }

    func loadRemovalTransportInventory(_ original: OriginalContent) -> BackendOutcome<OriginalRemovalTransportInventory> {
        do {
            return .succeeded(try transaction(write: false) { document in
                try document.removalTransportInventory(original, epoch: reconciliationEpoch, projection: document.replayStore())
            })
        } catch ExplorationStorageError.unknownSchema { return .failed(.unknownSchema) }
        catch ExplorationStorageError.corruptStore { return .failed(.corruptStore) }
        catch { return .unknown }
    }

    func commitOriginal(_ mutation: OriginalStoreMutation) -> OriginalStoreCommitResult {
        do {
            let receipt = try transaction(write: true) { try $0.applyOriginal(mutation, supportedVerificationSchemas: supportedVerificationSchemas,
                reconciliationEpoch: reconciliationEpoch) }
            if fault == .afterDiskCommitBeforeReply { return .unavailable(.inaccessible) }
            return .committed(receipt)
        } catch let error as BackendContractError { return .rejected(error) }
        catch { return .unavailable(.inaccessible) }
    }

    func commitRemovalObservation(_ mutation: OriginalStoreMutation,
        check: @Sendable () throws -> Void) -> OriginalStoreCommitResult {
        guard case .resolveRemoval = mutation.change else { return .rejected(.wrongStage) }
        do {
            let receipt = try transaction(write: true) { document in
                if let previous = document.originalJournal.first(where: { $0.mutation.operation == mutation.operation }) {
                    guard previous.mutation == mutation else { throw BackendContractError.identityMismatch }
                    return previous.receipt
                }
                guard document.transactionRevision == mutation.expectedRevision else { throw BackendContractError.revisionConflict }
                // The file check and descriptor close happen before persistence,
                // under the same process-shared writer lock as physical unlink.
                try check()
                return try document.applyOriginal(mutation, supportedVerificationSchemas: supportedVerificationSchemas,
                    reconciliationEpoch: reconciliationEpoch)
            }
            if fault == .afterDiskCommitBeforeReply { return .unavailable(.inaccessible) }
            return .committed(receipt)
        } catch let error as BackendContractError { return .rejected(error) }
        catch { return .unavailable(.inaccessible) }
    }

    func lookupOriginalCommit(_ mutation: OriginalStoreMutation) -> BackendOutcome<OriginalStoreCommitReceipt> {
        do {
            return try transaction(write: false) { document in
                guard let stored = document.originalJournal.first(where: { $0.mutation.operation == mutation.operation }) else { return .notExecuted }
                guard stored.mutation == mutation else { return .failed(.rejected) }
                return .succeeded(stored.receipt)
            }
        } catch { return .unknown }
    }

    func performRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        effect: @Sendable () throws -> Void) -> BackendOutcome<RemovalResolutionReceipt> {
        do {
            return try transaction(write: false) { document in
                let projection = try document.replayStore()
                let inventory = try boundary.transportFence.map { _ in
                    try document.removalTransportInventory(boundary.target.original, epoch: reconciliationEpoch, projection: projection)
                }
                let backend: BackendStoreSnapshot?
                if boundary.transportFence == nil { backend = nil }
                else { backend = try projection.snapshot(revision: document.transactionRevision, storeIdentity: document.storeIdentity) }
                try projection.validatesRemovalBoundary(boundary,
                    revision: document.transactionRevision, epoch: reconciliationEpoch, transportInventory: inventory,
                    backend: backend)
                if boundary.intent.purpose == .cleanup {
                    guard let reservation = document.originalJournal.last(where: { entry in
                        if case .reserveCleanup(let intent, _, _, _) = entry.mutation.change { return intent == boundary.intent }
                        return false
                    }), case .reserveCleanup(_, let selection, _, _) = reservation.mutation.change else {
                        throw BackendContractError.notCommitted
                    }
                    let currentSchema = try projection.cleanupSchema(original: boundary.intent.original, selection: selection)
                    guard reservation.acceptedVerificationSchema == currentSchema,
                          supportedVerificationSchemas.contains(currentSchema) else { throw BackendContractError.unsupportedVersion }
                }
                // The durable reservation cannot be resolved or replaced while
                // this short writer transaction holds its process-shared lock.
                do { try effect() }
                catch { return .failed(.inaccessible) }
                return .succeeded(.init(intent: boundary.intent, resolution: .removed))
            }
        } catch is BackendContractError { return .notExecuted }
        catch { return .unknown }
    }

    func establishRegistrationIdentity(expectedRevision: UInt64,
        expectedIdentity: RegistrationStoreIdentity?) throws -> RegistrationStoreIdentity {
        let identity = try transaction(write: true) { document in
            if let expectedIdentity, document.storeIdentity != expectedIdentity { throw BackendContractError.identityMismatch }
            guard document.transactionRevision == expectedRevision else { throw BackendContractError.revisionConflict }
            if let identity = document.storeIdentity { return identity }
            let identity = RegistrationStoreIdentity(rawValue: UUID())
            document.storeIdentity = identity
            try document.validate()
            return identity
        }
        if fault == .afterDiskCommitBeforeReply { throw ExplorationStorageError.inaccessible }
        return identity
    }

    func loadBackend() -> BackendStoreLoadResult {
        do { return .loaded(try transaction(write: false) { try $0.replayStore().snapshot(revision: $0.transactionRevision, storeIdentity: $0.storeIdentity) }) }
        catch ExplorationStorageError.unknownSchema { return .unavailable(.unknownSchema) }
        catch ExplorationStorageError.corruptStore { return .unavailable(.corruptStore) }
        catch { return .unavailable(.inaccessible) }
    }

    func commitBackend(_ mutation: BackendStoreMutation) -> BackendCommitResult {
        do {
            let identity = mutation.change.key.operationIdentity
            let receipt = try transaction(write: true, backendIdentity: identity) {
                try $0.applyBackend(mutation, reconciliationEpoch: reconciliationEpoch)
            }
            return fault?.losesReply(identity) == true ? .unknown : .committed(receipt)
        } catch let error as BackendContractError { return .rejected(error) }
        catch ExplorationStorageError.unknownSchema { return .unavailable(.unknownSchema) }
        catch ExplorationStorageError.corruptStore { return .unavailable(.corruptStore) }
        catch { return .unavailable(.inaccessible) }
    }

    func lookupBackend(_ mutation: BackendStoreMutation) -> BackendCommitResult {
        do { return try transaction(write: false) { $0.lookupBackend(mutation) } }
        catch ExplorationStorageError.unknownSchema { return .unavailable(.unknownSchema) }
        catch ExplorationStorageError.corruptStore { return .unavailable(.corruptStore) }
        catch { return .unavailable(.inaccessible) }
    }

    func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) -> BackendOutcome<InvalidationID> {
        do {
            return try transaction(write: false) { document in
                let projection = try document.replayStore()
                guard acknowledgement.isCommitted, projection.invalidations.contains(acknowledgement),
                      projection.allOutbox.contains(.invalidation(acknowledgement)) else { return .unknown }
                return .succeeded(acknowledgement.record.id)
            }
        } catch ExplorationStorageError.unknownSchema { return .failed(.unknownSchema) }
        catch ExplorationStorageError.corruptStore { return .failed(.corruptStore) }
        catch { return .failed(.inaccessible) }
    }

}
