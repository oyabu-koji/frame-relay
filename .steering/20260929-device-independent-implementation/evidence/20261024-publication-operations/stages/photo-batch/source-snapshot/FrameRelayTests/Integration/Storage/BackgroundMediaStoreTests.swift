import CoreData
import Foundation
import Testing
@testable import FrameRelay

/// Real disk/managed-original lease I/O with explicitly synthetic OS/source
/// facts. Actual URLSession callbacks and source copies have separate B tests.
struct BackgroundMediaStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func exactEventsReopenWithoutPromotingRemoteOrReleasingReaders(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundStoreFixture.make(run, candidate: candidate)
            let request = try #require(try await mediaSnapshot(fixture.store).requests.first)
            for (index, change) in fixture.changes.enumerated() {
                _ = try await fixture.write("event-\(index)", change)
                let reopened = try backgroundDisk(run, candidate: candidate)
                let state = try #require(try await mediaSnapshot(reopened).backgroundTasks.first)
                #expect(state.events.count == index + 1)
                #expect(state.events.last?.change == change)
                let exact = try #require(state.events.last)
                #expect(await reopened.lookupCommit(exact.mutation) == .committed(exact.commit))
                #expect(await reopened.commit(exact.mutation) == .committed(exact.commit))
                #expect(try await mediaSnapshot(reopened).requests.first == request)
                #expect(try await mediaOriginalSnapshot(reopened).originals.first?.readers == [fixture.lease])
            }
            let complete = try #require(try await mediaSnapshot(fixture.store).backgroundTasks.first)
            #expect(complete.resumeRequested && complete.stopRequested)
            #expect(complete.terminal?.outcome == .cancelled && complete.ownerClosure != nil)
            #expect(await fixture.files.observeFile(fixture.binding.reference) == .present(byteCount: fixture.binding.original.content.byteCount))
            await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases, BackgroundStoreInterruption.all)
    func everyCommitBoundaryRetainsExactPayloadAcrossLostReplyAndReopen(candidate: StorageCandidate,
        point: BackgroundStoreInterruption) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundStoreFixture.make(run, candidate: candidate)
            for index in 0..<point.index { _ = try await fixture.write("prefix-\(index)", fixture.changes[index]) }
            let before = try await mediaSnapshot(fixture.store)
            let command = MediaOperationID(rawValue: "interrupted-background-event")
            let mutation = BackendStoreMutation(expectedRevision: before.revision,
                change: .backgroundTask(command: command, value: fixture.changes[point.index]),
                expectedStoreIdentity: fixture.intent.context.storeIdentity)
            let fault: RecordingStoreFault = point.afterCommit
                ? .afterBackendCommitBeforeReply(.backgroundTask(command)) : .beforeBackendCommit(.backgroundTask(command))
            let interrupted = try backgroundDisk(run, candidate: candidate, fault: fault)
            #expect(await interrupted.commit(mutation) == (point.afterCommit ? .unknown : .unavailable(.inaccessible)))
            let reopened = try backgroundDisk(run, candidate: candidate)
            let after = try await mediaSnapshot(reopened)
            if point.afterCommit {
                let event = try #require(after.backgroundTasks.first?.events.last)
                #expect(event.mutation == mutation)
                #expect(event.change == fixture.changes[point.index])
                #expect(await reopened.lookupCommit(mutation) == .committed(event.commit))
                #expect(await reopened.commit(mutation) == .committed(event.commit))
                let changed = BackendStoreMutation(expectedRevision: mutation.expectedRevision + 1,
                    change: mutation.change, expectedStoreIdentity: mutation.expectedStoreIdentity)
                #expect(await reopened.lookupCommit(changed) == .rejected(.identityMismatch))
                #expect(try await mediaSnapshot(reopened) == after)
            } else {
                #expect(after == before)
                #expect(await reopened.lookupCommit(mutation) == .unknown)
            }
            #expect(after.requests == before.requests && after.verifications == before.verifications)
            #expect(try await mediaOriginalSnapshot(reopened).originals.first?.readers == [fixture.lease])
            await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func lateExactTerminalAndClosureStayWithTheOldRegistration(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundStoreFixture.make(run, candidate: candidate)
            _ = try await fixture.write("prepare", fixture.changes[0])
            _ = try await fixture.write("attach", fixture.changes[1])
            let current = try await mediaRegister(fixture.store, registration: .init(destination: fixture.intent.context.registration.destination,
                id: .init(rawValue: "replacement-background-registration"), generation: .init(rawValue: 2)))
            let rejected = try await fixture.mutation("late-resume", fixture.changes[2])
            #expect(await fixture.store.commit(rejected) == .rejected(.notCommitted))
            let old = fixture.intent.context
            let retargeted = backgroundCopyIntent(fixture.intent, context: .init(operation: old.operation, attempt: old.attempt,
                target: old.target, registration: current, gateGeneration: old.gateGeneration, storeIdentity: old.storeIdentity))
            let changed = try await fixture.mutation("retargeted-terminal", .terminal(retargeted,
                .init(binding: fixture.bindingValue, outcome: .cancelled)))
            #expect(await fixture.store.commit(changed) == .rejected(.identityMismatch))
            _ = try await fixture.write("late-terminal", fixture.changes[4])
            _ = try await fixture.write("late-close", fixture.changes[5])
            let reopened = try backgroundDisk(run, candidate: candidate)
            let snapshot = try await mediaSnapshot(reopened)
            let state = try #require(snapshot.backgroundTasks.first)
            #expect(state.intent.context.registration == fixture.intent.context.registration)
            #expect(state.intent.context.registration != current && state.ownerClosure != nil)
            #expect(!state.resumeRequested)
            #expect(snapshot.requests.first?.registration == fixture.intent.context.registration)
            #expect(snapshot.requests.first?.remote == .notExecuted)
            #expect(snapshot.verifications.isEmpty)
            #expect(try await mediaOriginalSnapshot(reopened).originals.first?.readers == [fixture.lease])
            await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func exactLiveLeaseSurvivesAccessAdvanceButDuplicateOSBindingsDoNot(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundStoreFixture.make(run, candidate: candidate)
            let second = try await backgroundPrepareRequest(store: fixture.store, access: fixture.access, binding: fixture.binding,
                identity: fixture.intent.context.storeIdentity, registration: fixture.intent.context.registration,
                name: "second-background", session: fixture.intent.session)
            let current = try #require(try await mediaOriginalSnapshot(fixture.store).originals.first)
            #expect(current.accessGeneration.rawValue > fixture.lease.accessGeneration.rawValue)
            #expect(current.readers.contains(fixture.lease))
            _ = try await fixture.write("older-exact-live-lease", fixture.changes[0])
            _ = try await fixture.write("first-attach", fixture.changes[1])
            _ = try await fixture.write("first-resume", fixture.changes[2])
            _ = try await fixture.write("first-terminal", fixture.changes[4])
            _ = try await fixture.write("first-close", fixture.changes[5])
            let anotherGeneration = backgroundCopyIntent(second.0,
                session: .init(identifier: fixture.intent.session.identifier, generation: .init(rawValue: UUID())))
            let generationReuse = try await fixture.mutation("os-identifier-new-generation", .prepared(anotherGeneration))
            #expect(await fixture.store.commit(generationReuse) == .rejected(.duplicateTarget))
            let copied = backgroundCopyIntent(second.0, description: fixture.intent.taskDescription)
            let duplicateDescription = try await fixture.mutation("duplicate-description", .prepared(copied))
            #expect(await fixture.store.commit(duplicateDescription) == .rejected(.duplicateTarget))
            _ = try await fixture.write("second-prepare", .prepared(second.0))
            let reused = BackgroundMediaTaskBinding(session: second.0.session, taskIdentifier: fixture.bindingValue.taskIdentifier,
                taskDescription: second.0.taskDescription)
            let numericReuse = try await fixture.mutation("numeric-reuse", .attached(second.0, reused))
            #expect(await fixture.store.commit(numericReuse) == .rejected(.identityMismatch))
            let anotherID = backgroundCopyIntent(fixture.intent, id: .init(rawValue: UUID().uuidString))
            let recreation = try await fixture.mutation("same-attempt-recreation", .prepared(anotherID))
            #expect(await fixture.store.commit(recreation) == .rejected(.duplicateTarget))
            let tasks = try await mediaSnapshot(fixture.store).backgroundTasks
            #expect(tasks.count == 2 && tasks.first?.resumeRequested == true && tasks.last?.binding == nil)
            #expect(await fixture.access.releaseRead(second.1) == .succeeded(.init(lease: second.1)))
            await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["pause", "saving", "released"])
    func resumeRechecksCurrentRequestAndExactLease(candidate: StorageCandidate, blocker: String) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundStoreFixture.make(run, candidate: candidate)
            _ = try await fixture.write("prepare", fixture.changes[0])
            _ = try await fixture.write("attach", fixture.changes[1])
            if blocker == "released" {
                #expect(await fixture.access.releaseRead(fixture.lease) == .succeeded(.init(lease: fixture.lease)))
            } else {
                _ = try await mediaCommit(fixture.store, .requestTransition(command: .init(rawValue: "current-blocker"),
                    operation: fixture.intent.context.operation, target: fixture.intent.context.target,
                    registration: fixture.intent.context.registration,
                    value: blocker == "pause" ? .pause : .wait(.saving, active: true)))
            }
            let resume = try await fixture.mutation("blocked-resume", fixture.changes[2])
            #expect(await fixture.store.commit(resume) == .rejected(blocker == "released" ? .readersActive : .deletionUnresolved))
            #expect(try await mediaSnapshot(fixture.store).backgroundTasks.first?.resumeRequested == false)
            // An actual late callback remains recordable; it does not override
            // the user's pause or the independently persisted saving wait.
            _ = try await fixture.write("actual-late-terminal", fixture.changes[4])
            #expect(try await mediaSnapshot(fixture.store).requests.first?.remote == .notExecuted)
            await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func storeGuardAndFullMutationLookupRejectMissingOrChangedAuthority(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundStoreFixture.make(run, candidate: candidate)
            let exact = try await fixture.mutation("exact-prepare", fixture.changes[0])
            let absent = BackendStoreMutation(expectedRevision: exact.expectedRevision, change: exact.change)
            #expect(await fixture.store.commit(absent) == .rejected(.identityMismatch))
            let wrong = BackendStoreMutation(expectedRevision: exact.expectedRevision, change: exact.change,
                expectedStoreIdentity: .init(rawValue: UUID()))
            #expect(await fixture.store.commit(wrong) == .rejected(.identityMismatch))
            guard case .committed(let receipt) = await fixture.store.commit(exact) else { throw BackendContractError.notCommitted }
            let altered = backgroundCopyIntent(fixture.intent, description: UUID().uuidString)
            let changed = BackendStoreMutation(expectedRevision: exact.expectedRevision,
                change: .backgroundTask(command: .init(rawValue: "exact-prepare"), value: .prepared(altered)),
                expectedStoreIdentity: exact.expectedStoreIdentity)
            #expect(await fixture.store.commit(changed) == .rejected(.identityMismatch))
            #expect(await fixture.store.lookupCommit(changed) == .rejected(.identityMismatch))
            #expect(await fixture.store.lookupCommit(exact) == .committed(receipt))
            let gapTerminal = try await fixture.mutation("unattached-terminal", fixture.changes[4])
            #expect(await fixture.store.commit(gapTerminal) == .rejected(.identityMismatch))
            let gapClose = try await fixture.mutation("unattached-close", fixture.changes[5])
            #expect(await fixture.store.commit(gapClose) == .rejected(.identityMismatch))
            #expect(try await mediaSnapshot(fixture.store).backgroundTasks.first?.binding == nil)
            await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func downloadKeepsFixedRangeAndRequiresTheCurrentMediaEpochOnlyForNewResume(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundStoreFixture.make(run, candidate: candidate)
            let rendition = publicationRendition(fixture.binding.original)
            let registration = fixture.intent.context.registration
            _ = try await mediaCommit(fixture.store, .publication(mediaPublication(rendition, registration: registration)))
            let operation = MediaOperationID(rawValue: "background-download-request")
            let attempt = TransferAttemptID(rawValue: "background-download-attempt")
            let request = MediaRequest(operation: operation, target: .rendition(rendition), purpose: .download,
                registration: registration, expectedStartRevision: try await mediaSnapshot(fixture.store).revision)
            _ = try await mediaCommit(fixture.store, .request(command: operation, value: request))
            _ = try await mediaCommit(fixture.store, .requestTransition(command: .init(rawValue: "download-remote"), operation: operation,
                target: request.target, registration: registration,
                value: .reconciled(.init(context: .init(operation: operation, registration: registration, target: request.target, session: nil),
                    observation: .init(rawValue: 1), result: .notExecuted))))
            _ = try await mediaCommit(fixture.store, .requestTransition(command: .init(rawValue: "download-attempt"), operation: operation,
                target: request.target, registration: registration, value: .beginAttempt(attempt)))
            let leases = RenditionReadLeases(store: fixture.store)
            let lease = try await leases.acquire(rendition: rendition, registration: registration, operation: operation, context: .transport(attempt))
            let range = try MediaByteRange(lowerBound: 0, upperBound: min(16, rendition.deliveryContent.byteCount))
            let intent = BackgroundMediaTaskIntent(id: .init(rawValue: UUID().uuidString),
                context: .init(operation: operation, attempt: attempt, target: request.target, registration: registration,
                    gateGeneration: 92, storeIdentity: fixture.intent.context.storeIdentity),
                session: fixture.intent.session, taskDescription: UUID().uuidString, requestFingerprint: fixture.intent.requestFingerprint,
                source: .download(rendition: rendition, range: range, lease: lease))
            let binding = BackgroundMediaTaskBinding(session: intent.session, taskIdentifier: 19, taskDescription: intent.taskDescription)
            _ = try await fixture.write("download-prepared", .prepared(intent))
            _ = try await fixture.write("download-attached", .attached(intent, binding))
            let reopened = try backgroundDisk(run, candidate: candidate)
            let resume = try await fixture.mutation("download-resume", .resumeRequested(intent, binding))
            #expect(await reopened.commit(resume) == .rejected(.staleGeneration))
            guard case .committed = await fixture.store.commit(resume) else { throw BackendContractError.notCommitted }
            let terminal = try await fixture.mutation("download-terminal", .terminal(intent, .init(binding: binding, outcome: .cancelled)))
            guard case .committed = await reopened.commit(terminal) else { throw BackendContractError.notCommitted }
            let closure = try await fixture.mutation("download-closed", .ownerClosed(intent,
                .init(binding: binding, uploadSource: nil, tasksJoined: true, handlesClosed: true)))
            guard case .committed = await reopened.commit(closure) else { throw BackendContractError.notCommitted }
            let state = try #require(try await mediaSnapshot(reopened).backgroundTasks.first)
            #expect(state.intent.source == .download(rendition: rendition, range: range, lease: lease))
            #expect(state.ownerClosure != nil && state.terminal?.outcome == .cancelled)
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.first?.mediaReaders.contains(lease) == true)
            #expect(try await mediaSnapshot(reopened).requests.last?.remote == .notExecuted)
            try await leases.release(lease)
            await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [6, 7])
    func preBackgroundDocumentsRemainEmptyAndUnmodifiedOnRead(candidate: StorageCandidate, schema: Int) async throws {
        try await withStorageRun { run in
            let bytes = Data("{\"schema\":\(schema),\"entries\":[],\"transactionRevision\":0,\"originalJournal\":[],\"backendJournal\":[],\"legacyRevision\":0}".utf8)
            if candidate == .atomicFile {
                try bytes.write(to: run.url.appendingPathComponent(candidate.fileName), options: .withoutOverwriting)
            } else {
                let context = try backgroundPayloadContext(run)
                try context.performAndWait {
                    let row = NSEntityDescription.insertNewObject(forEntityName: "Document", into: context)
                    row.setValue(bytes, forKey: "payload"); try context.save()
                }
            }
            let store = try backgroundDisk(run, candidate: candidate)
            let snapshot = try await mediaSnapshot(store)
            #expect(snapshot.backgroundTasks.isEmpty && snapshot.storeIdentity == nil && snapshot.revision == 0)
            let reopened = try backgroundDisk(run, candidate: candidate)
            #expect(try await mediaSnapshot(reopened) == snapshot)
            let unchanged: Data
            if candidate == .atomicFile { unchanged = try Data(contentsOf: run.url.appendingPathComponent(candidate.fileName)) }
            else {
                let context = try backgroundPayloadContext(run)
                unchanged = try context.performAndWait {
                    let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Document"))
                    return try #require(rows.first?.value(forKey: "payload") as? Data)
                }
            }
            #expect(unchanged == bytes)
        }
    }
}

nonisolated struct BackgroundStoreInterruption: Sendable {
    let index: Int
    let afterCommit: Bool
    static var all: [Self] { (0..<6).flatMap { index in [Self(index: index, afterCommit: false), Self(index: index, afterCommit: true)] } }
}

nonisolated private struct BackgroundStoreFixture {
    let store: any MediaDiskStore
    let files: ManagedOriginalStore
    let access: ManagedOriginalAccess
    let binding: OriginalBinding
    let lease: OriginalReadLease
    let intent: BackgroundMediaTaskIntent
    var bindingValue: BackgroundMediaTaskBinding { .init(session: intent.session, taskIdentifier: 7, taskDescription: intent.taskDescription) }
    var changes: [BackgroundMediaTaskChange] {
        let file: ManagedUploadSourceIdentity?
        if case .upload(_, _, let value) = intent.source { file = value } else { file = nil }
        return [.prepared(intent), .attached(intent, bindingValue), .resumeRequested(intent, bindingValue), .stopRequested(intent),
            .terminal(intent, .init(binding: bindingValue, outcome: .cancelled)),
            .ownerClosed(intent, .init(binding: bindingValue, uploadSource: file, tasksJoined: true, handlesClosed: true))]
    }
    static func make(_ run: ExplorationRunDirectory, candidate: StorageCandidate) async throws -> Self {
        let original = try OriginalRemovalFixture(run: run, candidate: candidate)
        let binding = try await original.original("background-store-original")
        let before = try await mediaSnapshot(original.store)
        let identity = try await original.store.establishRegistrationIdentity(expectedRevision: before.revision, expectedIdentity: nil)
        let registration = try await mediaRegister(original.store)
        let (intent, lease) = try await backgroundPrepareRequest(store: original.store, access: original.access, binding: binding,
            identity: identity, registration: registration, name: "background-request",
            session: .init(identifier: .init(rawValue: "com.framerelay.synthetic." + UUID().uuidString), generation: .init(rawValue: UUID())))
        return .init(store: original.store, files: original.files, access: original.access, binding: binding, lease: lease, intent: intent)
    }
    func mutation(_ command: String, _ change: BackgroundMediaTaskChange) async throws -> BackendStoreMutation {
        .init(expectedRevision: try await mediaSnapshot(store).revision,
            change: .backgroundTask(command: .init(rawValue: command), value: change), expectedStoreIdentity: intent.context.storeIdentity)
    }
    func write(_ command: String, _ change: BackgroundMediaTaskChange) async throws -> BackendCommitReceipt {
        let mutation = try await mutation(command, change)
        guard case .committed(let receipt) = await store.commit(mutation) else { throw BackendContractError.notCommitted }
        return receipt
    }
    func close() async {
        if case .succeeded(let snapshot) = await store.loadOriginalState(), snapshot.originals.contains(where: { $0.readers.contains(lease) }) {
            #expect(await access.releaseRead(lease) == .succeeded(.init(lease: lease)))
        }
    }
}

nonisolated private func backgroundPrepareRequest(store: any MediaDiskStore, access: ManagedOriginalAccess,
    binding: OriginalBinding, identity: RegistrationStoreIdentity, registration: RegistrationIdentity, name: String,
    session: BackgroundMediaSessionIdentity) async throws -> (BackgroundMediaTaskIntent, OriginalReadLease) {
    let operation = MediaOperationID(rawValue: name)
    let attempt = TransferAttemptID(rawValue: name + "-attempt")
    let mac = UploadSessionID(rawValue: name + "-mac-session")
    let before = try await mediaSnapshot(store)
    let request = MediaRequest(operation: operation, target: .original(binding.original), purpose: .upload,
        registration: registration, expectedStartRevision: before.revision)
    _ = try await mediaCommit(store, .request(command: operation, value: request))
    _ = try await mediaCommit(store, .requestTransition(command: .init(rawValue: name + "-remote"), operation: operation,
        target: request.target, registration: registration,
        value: .reconciled(.init(context: .init(operation: operation, registration: registration, target: request.target, session: mac),
            observation: .init(rawValue: 1), result: .notExecuted))))
    _ = try await mediaCommit(store, .requestTransition(command: .init(rawValue: name + "-begin"), operation: operation,
        target: request.target, registration: registration, value: .beginAttempt(attempt)))
    guard case .succeeded(let lease) = await access.acquireRead(binding.original, operation: operation,
        leaseID: .init(rawValue: name + "-reader")) else { throw BackendContractError.readersActive }
    let source = ManagedUploadSourceIdentity(id: .init(rawValue: UUID().uuidString), directoryDevice: 1, directoryInode: 2,
        file: .init(device: 1, inode: 3, size: Int64(binding.original.content.byteCount), modifiedSeconds: 1,
            modifiedNanoseconds: 0, changedSeconds: 1, changedNanoseconds: 0), content: binding.original.content)
    let intent = BackgroundMediaTaskIntent(id: .init(rawValue: UUID().uuidString), context: .init(operation: operation, attempt: attempt,
        target: request.target, registration: registration, gateGeneration: 37, storeIdentity: identity), session: session,
        taskDescription: UUID().uuidString, requestFingerprint: .init(sha256: String(repeating: "b", count: 64)),
        source: .upload(session: mac, lease: lease, source: source))
    return (intent, lease)
}

nonisolated private func backgroundCopyIntent(_ intent: BackgroundMediaTaskIntent, id: BackgroundMediaTaskID? = nil,
    context: BackgroundMediaRequestContext? = nil,
    session: BackgroundMediaSessionIdentity? = nil,
    description: String? = nil) -> BackgroundMediaTaskIntent {
    .init(id: id ?? intent.id, context: context ?? intent.context, session: session ?? intent.session, taskDescription: description ?? intent.taskDescription,
        requestFingerprint: intent.requestFingerprint, source: intent.source)
}
nonisolated private func backgroundDisk(_ run: ExplorationRunDirectory, candidate: StorageCandidate,
    fault: RecordingStoreFault? = nil) throws -> any MediaDiskStore {
    switch candidate {
    case .atomicFile: return try AtomicFileRecordingStore(run: .openExisting(at: run.url), mode: .openExisting, fault: fault)
    case .sqlite: return try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting, fault: fault)
    }
}

nonisolated private func backgroundPayloadContext(_ run: ExplorationRunDirectory) throws -> NSManagedObjectContext {
    let entity = NSEntityDescription(); entity.name = "Document"; entity.managedObjectClassName = "NSManagedObject"
    let payload = NSAttributeDescription(); payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
    entity.properties = [payload]
    let model = NSManagedObjectModel(); model.entities = [entity]; model.versionIdentifiers = ["FrameRelay-D04-v1"]
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: run.url.appendingPathComponent("recordings.sqlite"))
    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    return context
}
