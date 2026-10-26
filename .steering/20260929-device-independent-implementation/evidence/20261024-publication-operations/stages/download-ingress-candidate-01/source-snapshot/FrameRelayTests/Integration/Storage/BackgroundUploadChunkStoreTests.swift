import Foundation
import Testing
@testable import FrameRelay

/// Actual new disks/original bytes and writer receipts. SDK terminals, chunk
/// file identities and server replies are explicit synthetic contract inputs;
/// these tests do not prove a network send, native stop or formal producer.
struct BackgroundUploadChunkStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func allAttemptsReopenWithFreshGetAfterEachActualStopAndNoWholeCompletion(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession()
            let get1 = try await f.get(), first = try await f.attempt(get1)
            let currentView = try await f.view()
            try BackgroundUploadChunkAdmission.requireCurrentAttempt(first.intent, view: currentView)
            _ = try await f.event(.prepared(first.intent))
            let stopped1 = try await f.finish(first)
            var snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.requests[0].transport == .stopped && !snapshot.requests[0].hasReconciled)
            let get2 = try await f.get(indexes: [0]), nextID = BackgroundMediaTaskID(rawValue: UUID().uuidString)
            let sourceID = ManagedUploadSourceID(rawValue: UUID().uuidString), context = f.context()
            let nextView = try await f.view()
            try BackgroundUploadChunkAdmission.requireBeforeAttempt(context: context, range: f.range(index: 1),
                metadata: .init(get2), taskID: nextID, sourceID: sourceID, view: nextView)
            let second = try await f.attempt(get2, index: 1, context: context, taskID: nextID, sourceID: sourceID)
            _ = try await f.event(.prepared(second.intent))
            let stopped2 = try await f.finish(second)
            snapshot = try await mediaSnapshot(f.store)
            let stops = try #require(OriginalRemovalTransportHistory.stoppedTasks(f.source.original, backend: snapshot))
            #expect(stops.map(\.attempt) == [first.intent.context.attempt, second.intent.context.attempt])
            let allOwnersClosed = snapshot.backgroundTasks.allSatisfy { $0.ownerClosure != nil }
            #expect(snapshot.backgroundTasks.count == 2 && allOwnersClosed)
            let inventory = try await f.inventory()
            #expect(BackgroundStoppedTransportObservation(inventory: inventory, stops: stops).validatesHistory(snapshot))
            #expect(!BackgroundStoppedTransportObservation(inventory: inventory, stops: Array(stops.suffix(1))).validatesHistory(snapshot))
            #expect(!BackgroundStoppedTransportObservation(inventory: inventory, stops: stops + stops).validatesHistory(snapshot))
            let missingFirst = OriginalRemovalTransportInventory(original: inventory.original, epoch: inventory.epoch,
                storeIdentity: inventory.storeIdentity, requests: inventory.requests, tasks: inventory.tasks,
                verifications: inventory.verifications, registrations: inventory.registrations,
                journal: inventory.journal.filter { fact in
                    if case .requestTransition(_, _, _, _, .stopped(let stop)) = fact.mutation.change {
                        return !UploadMetadataValidation.exact(stop.attempt, first.intent.context.attempt)
                    }
                    return true
                })
            #expect(!BackgroundStoppedTransportObservation(inventory: missingFirst, stops: stops).validatesHistory(snapshot))
            let target = OriginalRemovalTarget(original: f.source.original, reference: f.original.reference, operation: .init(rawValue: UUID().uuidString))
            let seal = OriginalRemovalAdmissionSeal(batch: .init(rawValue: UUID().uuidString), target: target, nonce: UUID().uuidString)
            #expect(OriginalRemovalTransportFence(seal: seal, inventory: inventory, stops: stops).validatesHistory(snapshot))
            #expect(!OriginalRemovalTransportFence(seal: seal, inventory: missingFirst, stops: stops).validatesHistory(snapshot))
            #expect(snapshot.requests[0].transport == .stopped && !snapshot.requests[0].hasReconciled)
            #expect(snapshot.requests[0].remote == .inProgress && snapshot.verifications.isEmpty && snapshot.outbox.isEmpty)
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers.isEmpty)
            #expect(try await mediaSnapshot(f.reopen()) == snapshot)
            let document = try await f.document(originals: [first.acquisition, stopped1.release, second.acquisition, stopped2.release])
            let projection = try document.replayStore()
            // A finished document's future GET/task facts cannot be borrowed
            // at an earlier transaction boundary, even with a later projection.
            #expect(throws: (any Error).self) {
                try document.requireUploadChunkHistory(second.intent, through: stopped1.stopped.committedRevision, projection: projection)
            }
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func reservedAttemptChecksDoNotNeedAnInventedDescriptorAndNeverClearPersonIntent(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let get = try await f.get()
            let context = f.context(), task = BackgroundMediaTaskID(rawValue: UUID().uuidString), source = ManagedUploadSourceID(rawValue: UUID().uuidString)
            let selection = try UploadChunkMetadataSelection(get), range = try f.range()
            let beforeView = try await f.view()
            try BackgroundUploadChunkAdmission.requireBeforeAttempt(context: context, range: range, metadata: selection,
                taskID: task, sourceID: source, view: beforeView)
            _ = try await f.transition(.beginAttempt(context.attempt))
            let reservedView = try await f.view()
            try BackgroundUploadChunkAdmission.requireReservedAttempt(context: context, range: range, metadata: selection,
                taskID: task, sourceID: source, lease: nil, view: reservedView)
            #expect(!(try await mediaSnapshot(f.store).requests[0].hasReconciled))
            let acquired = try await f.acquire()
            let acquiredView = try await f.view()
            try BackgroundUploadChunkAdmission.requireReservedAttempt(context: context, range: range, metadata: selection,
                taskID: task, sourceID: source, lease: acquired.lease, view: acquiredView)
            _ = try await f.transition(.pause)
            let paused = try await f.view()
            #expect(throws: BackendContractError.wrongStage) {
                try BackgroundUploadChunkAdmission.requireReservedAttempt(context: context, range: range, metadata: selection,
                    taskID: task, sourceID: source, lease: acquired.lease, view: paused)
            }
            #expect(try await mediaSnapshot(f.store).backgroundTasks.isEmpty)
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [acquired.lease])
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func aGetReservedBeforeStopCannotBecomeFreshByDelayingItsResponse(candidate: StorageCandidate, responseAfterStop: Bool) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let initialGet = try await f.get(), first = try await f.attempt(initialGet)
            _ = try await f.event(.prepared(first.intent))
            let query = try await f.begin(.lookup(f.metadataBinding.session))
            let response = UploadMetadataResponse.status(.init(binding: f.metadataBinding, state: .receiving,
                evidence: nil, chunkIndexes: [], failureCode: nil))
            let selected: StoredUploadMetadataObservation
            if responseAfterStop {
                _ = try await f.finish(first); selected = try await f.observe(query, response)
            } else {
                selected = try await f.observe(query, response); _ = try await f.finish(first)
            }
            let view = try await f.view(), context = f.context(), selection = try UploadChunkMetadataSelection(selected)
            #expect(throws: BackendContractError.staleGeneration) {
                try BackgroundUploadChunkAdmission.requireBeforeAttempt(context: context, range: f.range(index: 1), metadata: selection,
                    taskID: .init(rawValue: UUID().uuidString), sourceID: .init(rawValue: UUID().uuidString), view: view)
            }
            let second = try await f.attempt(selected, index: 1, context: context)
            let before = try await mediaSnapshot(f.store)
            #expect(await f.store.commit(try await f.mutation(.backgroundTask(command: .init(rawValue: UUID().uuidString),
                value: .prepared(second.intent)))) == .rejected(.staleGeneration))
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(try await mediaSnapshot(f.reopen()) == before)
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["release-before-close", "stop-before-release", "stop-before-close"])
    func everyReversedLocalTerminationOrderRefusesTheNextChunk(candidate: StorageCandidate, order: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let initialGet = try await f.get(), first = try await f.attempt(initialGet)
            _ = try await f.event(.prepared(first.intent)); _ = try await f.finish(first, order: order)
            let get = try await f.get(), second = try await f.attempt(get, index: 1)
            let before = try await mediaSnapshot(f.store)
            #expect(await f.store.commit(try await f.mutation(.backgroundTask(command: .init(rawValue: UUID().uuidString),
                value: .prepared(second.intent)))) == .rejected(.wrongStage))
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(try await mediaSnapshot(f.reopen()) == before)
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["unprepared", "unclosed", "unreleased"])
    func noOldOriginalOwnerCanBeDroppedWhenOnlyTheLatestRequestSaysStopped(candidate: StorageCandidate, gap: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let initialGet = try await f.get(), first = try await f.attempt(initialGet)
            if gap != "unprepared" { _ = try await f.event(.prepared(first.intent)) }
            if gap == "unclosed" {
                _ = try await f.event(.attached(first.intent, first.binding))
                _ = try await f.event(.terminal(first.intent, .init(binding: first.binding, outcome: .cancelled)))
                _ = try await f.originalChange(.release(first.lease))
            }
            if gap == "unreleased" {
                _ = try await f.event(.attached(first.intent, first.binding))
                _ = try await f.event(.terminal(first.intent, .init(binding: first.binding, outcome: .cancelled)))
                _ = try await f.event(.ownerClosed(first.intent, first.closure))
            }
            _ = try await f.transition(.stopped(first.stop))
            let get = try await f.get(), second = try await f.attempt(get, index: 1)
            let before = try await mediaSnapshot(f.store)
            #expect(chunkStoreIsRejected(await f.store.commit(try await f.mutation(.backgroundTask(
                command: .init(rawValue: UUID().uuidString), value: .prepared(second.intent))))))
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(try await mediaSnapshot(f.reopen()) == before)
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["uuid", "query", "fingerprint", "generation", "receipt", "target-alias"])
    func compactReferencesNeverBorrowAnUnrelatedActualObservation(candidate: StorageCandidate, field: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let get = try await f.get(), attempt = try await f.attempt(get)
            let changed: BackgroundMediaTaskIntent
            if field == "target-alias" {
                let original = OriginalContent(capture: .init(rawValue: f.source.original.capture.rawValue.replacingOccurrences(of: "\u{00e9}", with: "e\u{0301}")),
                    generation: f.source.original.generation, content: f.source.original.content)
                let old = attempt.intent.context
                let context = BackgroundMediaRequestContext(operation: old.operation, attempt: old.attempt, target: .original(original),
                    registration: old.registration, gateGeneration: old.gateGeneration, storeIdentity: old.storeIdentity)
                changed = .init(id: attempt.intent.id, context: context, session: attempt.intent.session,
                    taskDescription: attempt.intent.taskDescription, requestFingerprint: attempt.intent.requestFingerprint, source: attempt.intent.source)
            } else {
                let selection = try chunkStoreChangedSelection(try .init(get), field: field)
                changed = chunkStoreIntent(attempt.intent, source: .uploadChunk(lease: attempt.lease, chunk: attempt.chunk, metadata: selection))
            }
            let before = try await mediaSnapshot(f.store)
            #expect(chunkStoreIsRejected(await f.store.commit(try await f.mutation(.backgroundTask(
                command: .init(rawValue: UUID().uuidString), value: .prepared(changed))))))
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(try await mediaSnapshot(f.reopen()) == before)
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["post", "finalizing", "failed", "cancelled", "completed", "indexed", "new-query", "late-get"])
    func onlyTheLatestMissingReceivingGetFromBeforeThisAttemptCanPrepare(candidate: StorageCandidate, situation: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            let post = try await f.createSession(), good = try await f.get()
            let attempt = try await f.attempt(good)
            let selected: StoredUploadMetadataObservation
            switch situation {
            case "post": selected = post
            case "new-query": _ = try await f.begin(.lookup(f.metadataBinding.session)); selected = good
            case "indexed": selected = try await f.get(indexes: [0])
            case "late-get": selected = try await f.get()
            default: selected = try await f.get(state: try #require(UploadMetadataState(rawValue: situation)))
            }
            let intent = chunkStoreIntent(attempt.intent, source: .uploadChunk(lease: attempt.lease,
                chunk: attempt.chunk, metadata: try .init(selected)))
            let before = try await mediaSnapshot(f.store)
            #expect(chunkStoreIsRejected(await f.store.commit(try await f.mutation(.backgroundTask(
                command: .init(rawValue: UUID().uuidString), value: .prepared(intent))))))
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(try await mediaSnapshot(f.reopen()) == before)
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["pause", "cancel", "wait", "registration", "invalidation", "removal"])
    func writerRechecksEveryScopeAfterAnActualLeaseWasAllocated(candidate: StorageCandidate, race: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let initialGet = try await f.get(), attempt = try await f.attempt(initialGet)
            switch race {
            case "pause": _ = try await f.transition(.pause)
            case "cancel": _ = try await f.transition(.cancel)
            case "wait": _ = try await f.transition(.wait(.saving, active: true))
            case "registration":
                _ = try await mediaRegister(f.store, registration: .init(destination: f.metadataBinding.registration.destination,
                    id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
            case "invalidation":
                let rendition = statusRendition(f.source.original), registration = f.metadataBinding.registration
                _ = try await f.backend(.publication(mediaPublication(rendition, registration: registration)))
                _ = try await f.originalChange(.reserveInvalidation(.init(statusInvalidation(rendition, registration: registration,
                    id: "chunk-invalidation-" + UUID().uuidString))))
            default:
                _ = try await f.originalChange(.release(attempt.lease))
                let pending = try await mediaSnapshot(f.store), readers = try await mediaOriginalSnapshot(f.store)
                #expect(pending.requests[0].transport == .active && pending.backgroundTasks.isEmpty)
                #expect(readers.originals[0].readers.isEmpty)
                try await f.reserveRemoval()
            }
            let before = try await mediaSnapshot(f.store)
            let result = await f.store.commit(try await f.mutation(.backgroundTask(
                command: .init(rawValue: UUID().uuidString), value: .prepared(attempt.intent))))
            #expect(chunkStoreIsRejected(result))
            if race == "removal" { #expect(result == .rejected(.deletionUnresolved)) }
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(try await mediaSnapshot(f.reopen()) == before)
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["task", "source", "attempt", "lease"])
    func everyHistoricalIdentityIsReservedAcrossNewChunks(candidate: StorageCandidate, reused: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let initialGet = try await f.get(), first = try await f.attempt(initialGet)
            _ = try await f.event(.prepared(first.intent)); _ = try await f.finish(first)
            let get = try await f.get()
            if reused == "attempt" {
                #expect(await f.store.commit(try await f.transitionMutation(.beginAttempt(first.intent.context.attempt))) == .rejected(.wrongStage))
            } else {
                let second = try await f.attempt(get, index: 1, taskID: reused == "task" ? first.intent.id : .init(rawValue: UUID().uuidString),
                    sourceID: reused == "source" ? first.chunk.source.id : .init(rawValue: UUID().uuidString),
                    leaseID: reused == "lease" ? first.lease.id : .init(rawValue: UUID().uuidString))
                let before = try await mediaSnapshot(f.store)
                #expect(chunkStoreIsRejected(await f.store.commit(try await f.mutation(.backgroundTask(
                    command: .init(rawValue: UUID().uuidString), value: .prepared(second.intent))))))
                #expect(try await mediaSnapshot(f.store) == before)
            }
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func lostPreparedResponsesKeepTheExactEnvelopeAndCannotBorrowUTF8Alias(candidate: StorageCandidate, after: Bool) async throws {
        try await withStorageRun { run in
            let command = MediaOperationID(rawValue: "chunk-event-\u{00e9}")
            let fault: RecordingStoreFault = after ? .afterBackendCommitBeforeReply(.backgroundTask(command)) : .beforeBackendCommit(.backgroundTask(command))
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate, fault: fault)
            _ = try await f.createSession(); let initialGet = try await f.get(), attempt = try await f.attempt(initialGet)
            let mutation = try await f.mutation(.backgroundTask(command: command, value: .prepared(attempt.intent)))
            #expect(await f.store.commit(mutation) == (after ? .unknown : .unavailable(.inaccessible)))
            let reopened = try f.reopen(), snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.backgroundTasks.count == (after ? 1 : 0))
            if after {
                let event = try #require(snapshot.backgroundTasks[0].events.first)
                #expect(UploadMetadataValidation.exact(event.mutation, mutation))
                #expect(await reopened.lookupCommit(mutation) == .committed(event.commit))
                #expect(await reopened.commit(mutation) == .committed(event.commit))
                let alias = BackendStoreMutation(expectedRevision: mutation.expectedRevision,
                    change: .backgroundTask(command: .init(rawValue: "chunk-event-e\u{0301}"), value: .prepared(attempt.intent)),
                    expectedStoreIdentity: f.source.storeIdentity)
                #expect(await reopened.lookupCommit(alias) == .rejected(.identityMismatch))
                #expect(await reopened.commit(alias) == .rejected(.identityMismatch))
                #expect(await reopened.lookupCommit(.init(expectedRevision: mutation.expectedRevision + 1,
                    change: mutation.change, expectedStoreIdentity: f.source.storeIdentity)) == .rejected(.identityMismatch))
            } else { #expect(await reopened.lookupCommit(mutation) == .unknown) }
            #expect(await reopened.lookupCommit(.init(expectedRevision: mutation.expectedRevision, change: mutation.change,
                expectedStoreIdentity: .init(rawValue: UUID()))) == .rejected(.identityMismatch))
            #expect(try await mediaOriginalSnapshot(reopened).originals[0].readers == [attempt.lease])
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func historicalPreparationDoesNotReevaluateAgainstLaterQueriesRegistrationOrPersonControls(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let initialGet = try await f.get(), attempt = try await f.attempt(initialGet)
            let prepared = try await f.event(.prepared(attempt.intent))
            _ = try await f.event(.attached(attempt.intent, attempt.binding))
            // A newer observation shadows admission, not an already recorded fact.
            _ = try await f.get()
            _ = try await f.transition(.pause)
            _ = try await mediaRegister(f.store, registration: .init(destination: f.metadataBinding.registration.destination,
                id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
            let snapshot = try await mediaSnapshot(f.store), reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == snapshot)
            #expect(snapshot.backgroundTasks[0].events.first?.commit == prepared)
            #expect(snapshot.requests[0].intent == .paused && snapshot.requests[0].transport == .stopRequested)
            #expect(snapshot.backgroundTasks[0].ownerClosure == nil && snapshot.backgroundTasks[0].terminal == nil)
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func anOldWholeUploadKeepsItsSingleStopBranchAndCannotBeReusedAsChunkHistory(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let initialGet = try await f.get(), attempt = try await f.attempt(initialGet)
            let full = ManagedUploadSourceIdentity(id: attempt.chunk.source.id, directoryDevice: 1, directoryInode: 2,
                file: .init(device: 1, inode: 3, size: Int64(f.bytes.count), modifiedSeconds: 1, modifiedNanoseconds: 0,
                    changedSeconds: 1, changedNanoseconds: 0), content: f.source.original.content)
            let whole = ChunkStoreAttempt(intent: chunkStoreIntent(attempt.intent, source: .upload(session: f.metadataBinding.session,
                lease: attempt.lease, source: full)), lease: attempt.lease, chunk: attempt.chunk, acquisition: attempt.acquisition)
            _ = try await f.event(.prepared(whole.intent)); _ = try await f.finish(whole)
            let stopped = try await mediaSnapshot(f.store)
            #expect(OriginalRemovalTransportHistory.stoppedTasks(f.source.original, backend: stopped) == [whole.stop])
            let get = try await f.get(), second = try await f.attempt(get, index: 1)
            #expect(chunkStoreIsRejected(await f.store.commit(try await f.mutation(.backgroundTask(
                command: .init(rawValue: UUID().uuidString), value: .prepared(second.intent))))))
            #expect(try await mediaSnapshot(f.reopen()).backgroundTasks.count == 1)
            try await f.assertOriginal()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func recoveryRecognizesUploadKindWithoutAdoptingAReopenedChunkOwner(candidate: StorageCandidate, wrongKind: Bool) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run, candidate: candidate)
            _ = try await f.createSession(); let get = try await f.get(), attempt = try await f.attempt(get)
            _ = try await f.event(.prepared(attempt.intent)); _ = try await f.event(.attached(attempt.intent, attempt.binding))
            let observation = BackgroundMediaTaskObservation(session: attempt.binding.session, taskIdentifier: attempt.binding.taskIdentifier,
                taskDescription: attempt.binding.taskDescription, kind: wrongKind ? .download : .upload, state: .suspended,
                bytesSent: 0, bytesReceived: 0)
            let session = ChunkStoreRecoverySession.make([observation]), reopened = try f.reopen()
            let recovery = BackgroundMediaRecovery(store: reopened, identity: f.source.storeIdentity)
            guard case .succeeded(let report) = await recovery.reconcile(attempt.intent.session, session: session) else {
                throw BackendContractError.unavailable
            }
            #expect(report.tasks.count == 1 && report.tasks[0].disposition == (wrongKind ? .kindMismatch : .exact))
            #expect(await session.otherCalls == 0)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.backgroundTasks[0].terminal == nil && snapshot.backgroundTasks[0].ownerClosure == nil)
            #expect(try await mediaOriginalSnapshot(reopened).originals[0].readers == [attempt.lease])
            try await f.assertOriginal()
        }
    }
}

/// Shared only by the new UnitB suites. make creates one dedicated root's raw
/// 4096-byte original and queued acceptance; no SDK, Keychain or old data is used.
nonisolated struct BackgroundUploadChunkStoreFixture: Sendable {
    let run: ExplorationRunDirectory
    let candidate: StorageCandidate
    let store: any MediaDiskStore
    let files: ManagedOriginalStore
    let access: ManagedOriginalAccess
    let original: OriginalBinding
    let source: UploadMetadataRequest
    let bytes: Data
    let url: URL
    private let session: BackgroundMediaSessionIdentity
    private let recording: RecordingStoreDocument.Entry
    private let bindingFact: OriginalStoreJournalEntry

    static func make(_ run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite,
                     fault: RecordingStoreFault? = nil) async throws -> Self {
        let store: any MediaDiskStore
        switch candidate {
        case .atomicFile: store = try AtomicFileRecordingStore(run: run, mode: .createNew, fault: fault)
        case .sqlite: store = try SQLiteRecordingStore(run: run, mode: .createNew, fault: fault)
        }
        let input = try CaptureFixture(clip: "chunk-core-caf\u{00e9}-" + UUID().uuidString)
        let intent = RecordingIntent(context: input.context, operation: input.intent.operation, original: .init(rawValue: UUID().uuidString),
            trialReference: input.intent.trialReference, desired: input.desired, applied: input.applied, acceptedAt: input.time)
        guard case .committed(let intentCommit) = await store.execute(.commitIntent(input.token(1), expectedRevision: 0, intent)) else {
            throw BackendContractError.notCommitted
        }
        let files = ManagedOriginalStore(run: run), url = try await files.reserve(original: intent.original)
        let bytes = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try bytes.write(to: url, options: .withoutOverwriting)
        var lifecycle = try RecordingSaveLifecycle(intent: intent, intentToken: input.token(1), revision: 0)
        try lifecycle.acceptIntentCommit(intentCommit); try lifecycle.acceptRecordingEnd(context: input.context, evidence: input.end)
        try lifecycle.acceptFile(.init(context: input.context, original: intent.original, byteCount: UInt64(bytes.count), finalizedAt: input.time))
        _ = try lifecycle.acceptInspection(input.inspection(original: intent.original), resultToken: input.token(4))
        let result = try #require(lifecycle.resultRecord)
        guard case .committed(let save) = await store.execute(.commitResult(input.token(4), expectedRevision: 1, result)) else {
            throw BackendContractError.notCommitted
        }
        let digest = try await files.digest(for: intent.original)
        let binding = OriginalBinding(original: .init(capture: input.context.capture, generation: .init(rawValue: 1),
            content: try .init(byteCount: digest.byteCount, algorithm: "sha256", digest: digest.sha256)),
            reference: intent.original, saveRecord: result, saveCommit: save)
        let bindMutation = OriginalStoreMutation(operation: .init(rawValue: UUID().uuidString),
            expectedRevision: try await mediaOriginalSnapshot(store).revision, change: .bind(binding))
        guard case .committed(let bind) = await store.commitOriginal(bindMutation) else { throw BackendContractError.notCommitted }
        let registration = try await inventoryRegister(store), snapshot = try await mediaSnapshot(store)
        let identity = try #require(snapshot.storeIdentity), operation = MediaOperationID(rawValue: UUID().uuidString.lowercased())
        let request = try OriginalUploadAcceptanceRequest(parent: .init(rawValue: UUID().uuidString), storeIdentity: identity,
            registration: registration, scope: .single, targets: [.init(operation: operation, binding: binding)])
        let plan = try OriginalUploadAcceptancePlan(request: request, presences: [.present(byteCount: binding.original.content.byteCount)])
        guard case .committed = await store.commit(.init(expectedRevision: snapshot.revision,
            change: .originalUploadAcceptance(plan), expectedStoreIdentity: identity)) else { throw BackendContractError.notCommitted }
        let queued = try #require(try await mediaSnapshot(store).requests.first)
        return .init(run: run, candidate: candidate, store: store, files: files, access: ManagedOriginalAccess(store: store, originals: files),
            original: binding, source: try .init(storeIdentity: identity, registration: registration, operation: operation,
                original: binding.original, expectedStartRevision: queued.expectedStartRevision), bytes: bytes, url: url,
            session: .init(identifier: .init(rawValue: "com.framerelay.synthetic-chunk-store"), generation: .init(rawValue: UUID())),
            recording: .init(intentToken: input.token(1), intent: intent, revision: 2, resultToken: input.token(4), result: result),
            bindingFact: .init(mutation: bindMutation, receipt: bind))
    }

    var metadataBinding: UploadMetadataBinding {
        .init(registration: source.registration.server.registration, operation: source.operation, original: source.original,
            session: .init(rawValue: "2bb41993-4346-4f43-9487-8b635ca83d94"), chunkSize: 1536)
    }
    func range(index: UInt64 = 0) throws -> UploadChunkRange { try .init(binding: metadataBinding, index: index) }
    func context(attempt: TransferAttemptID = .init(rawValue: UUID().uuidString)) -> BackgroundMediaRequestContext {
        .init(operation: source.operation, attempt: attempt, target: .original(source.original), registration: metadataBinding.registration,
            gateGeneration: 17, storeIdentity: source.storeIdentity)
    }
    func begin(_ kind: UploadMetadataQueryKind) async throws -> CommittedUploadMetadataQuery {
        let snapshot = try await mediaSnapshot(store), request = try #require(snapshot.requests.first { $0.operation == source.operation })
        let query = try UploadMetadataQuery(id: .init(rawValue: UUID().uuidString), observationCommand: .init(rawValue: UUID().uuidString),
            request: source, kind: kind, generation: UploadMetadataGeneration.next(lastObservation: request.lastObservation,
                reservations: snapshot.uploadMetadataQueries.filter { $0.query.request.operation == source.operation }.map { $0.query.generation }))
        let receipt = try await backend(.uploadMetadata(.beginQuery(query)))
        return .init(query: query, commit: receipt, expectedStoreIdentity: source.storeIdentity)
    }
    func observe(_ query: CommittedUploadMetadataQuery, _ response: UploadMetadataResponse) async throws -> StoredUploadMetadataObservation {
        let observation = try UploadMetadataObservation(command: query.query.observationCommand, query: query, response: response)
        let receipt = try await backend(.uploadMetadata(.observe(observation)))
        return .init(observation: observation, commit: receipt, expectedStoreIdentity: source.storeIdentity)
    }
    func createSession() async throws -> StoredUploadMetadataObservation {
        let query = try await begin(.create)
        return try await observe(query, .created(metadataBinding))
    }
    func get(state: UploadMetadataState = .receiving, indexes: [UInt64] = []) async throws -> StoredUploadMetadataObservation {
        let query = try await begin(.lookup(metadataBinding.session))
        let evidence: UploadFinalReadEvidence? = state == .completed ? .init(id: .init(rawValue: UUID().uuidString),
            schemaVersion: "fr-final-read-v1", method: "final_destination_read_back", committed: true, finalSaveCompleted: true,
            sha256: source.original.content.digest, byteCount: source.original.content.byteCount,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)) : nil
        return try await observe(query, .status(.init(binding: metadataBinding, state: state,
            evidence: evidence, chunkIndexes: indexes, failureCode: state == .failed ? "synthetic-chunk-failure" : nil)))
    }
    func mutation(_ change: BackendStoreChange) async throws -> BackendStoreMutation {
        .init(expectedRevision: try await mediaSnapshot(store).revision, change: change, expectedStoreIdentity: source.storeIdentity)
    }
    func backend(_ change: BackendStoreChange) async throws -> BackendCommitReceipt {
        let mutation = try await self.mutation(change)
        guard case .committed(let receipt) = await store.commit(mutation),
              await store.lookupCommit(mutation) == .committed(receipt) else { throw BackendContractError.notCommitted }
        return receipt
    }
    func event(_ value: BackgroundMediaTaskChange) async throws -> BackendCommitReceipt {
        try await backend(.backgroundTask(command: .init(rawValue: UUID().uuidString), value: value))
    }
    func transitionMutation(_ value: MediaRequestTransition) async throws -> BackendStoreMutation {
        try await mutation(.requestTransition(command: .init(rawValue: UUID().uuidString), operation: source.operation,
            target: .original(source.original), registration: metadataBinding.registration, value: value))
    }
    func transition(_ value: MediaRequestTransition) async throws -> BackendCommitReceipt {
        let mutation = try await transitionMutation(value)
        guard case .committed(let receipt) = await store.commit(mutation) else { throw BackendContractError.notCommitted }
        return receipt
    }
    func originalChange(_ value: OriginalStoreChange, operation: MediaOperationID = .init(rawValue: UUID().uuidString)) async throws -> OriginalStoreJournalEntry {
        let mutation = OriginalStoreMutation(operation: operation,
            expectedRevision: try await mediaOriginalSnapshot(store).revision, change: value)
        guard case .committed(let receipt) = await store.commitOriginal(mutation) else { throw BackendContractError.notCommitted }
        return .init(mutation: mutation, receipt: receipt)
    }
    func acquire(leaseID: ReadLeaseID = .init(rawValue: UUID().uuidString)) async throws -> (lease: OriginalReadLease, fact: OriginalStoreJournalEntry) {
        let original = try #require(try await mediaOriginalSnapshot(store).logicalOriginals.first)
        let lease = OriginalReadLease(id: leaseID, original: source.original, operation: source.operation,
            accessGeneration: .init(rawValue: original.accessGeneration.rawValue + 1), epoch: .init(rawValue: "synthetic-chunk-original-epoch"))
        return (lease, try await originalChange(.acquire(lease)))
    }
    func inventory() async throws -> OriginalRemovalTransportInventory {
        guard case .succeeded(let value) = await store.loadRemovalTransportInventory(source.original) else { throw BackendContractError.unavailable }
        return value
    }
    func view() async throws -> BackgroundUploadChunkAdmissionView {
        let backend = try await mediaSnapshot(store), originals = try await mediaOriginalSnapshot(store), inventory = try await self.inventory()
        let latest = try await mediaSnapshot(store)
        guard backend.revision == originals.revision, latest == backend, inventory.matchesProjection(backend) else {
            throw BackendContractError.revisionConflict
        }
        return .init(revision: backend.revision, storeIdentity: backend.storeIdentity, registrations: backend.registrations,
            requests: backend.requests, originals: originals.logicalOriginals, queries: backend.uploadMetadataQueries,
            observations: backend.uploadMetadataObservations, tasks: backend.backgroundTasks, journal: inventory.journal)
    }
    func reopen() throws -> any MediaDiskStore {
        switch candidate {
        case .atomicFile: try AtomicFileRecordingStore(run: run, mode: .openExisting)
        case .sqlite: try SQLiteRecordingStore(run: run, mode: .openExisting)
        }
    }
    func assertOriginal() async throws {
        let digest = try await files.digest(for: original.reference)
        #expect(digest.sha256 == source.original.content.digest && digest.byteCount == UInt64(bytes.count))
        #expect(try Data(contentsOf: url) == bytes)
    }

    fileprivate func attempt(_ observation: StoredUploadMetadataObservation, index: UInt64 = 0,
        context override: BackgroundMediaRequestContext? = nil, taskID: BackgroundMediaTaskID = .init(rawValue: UUID().uuidString),
        sourceID: ManagedUploadSourceID = .init(rawValue: UUID().uuidString), leaseID: ReadLeaseID = .init(rawValue: UUID().uuidString)) async throws -> ChunkStoreAttempt {
        let context = override ?? self.context(), selected = try UploadChunkMetadataSelection(observation), range = try self.range(index: index)
        _ = try await transition(.beginAttempt(context.attempt))
        let acquired = try await acquire(leaseID: leaseID), content = try renditionContent(bytes.subdata(in: Int(range.offset)..<Int(range.upperBoundExclusive)))
        let descriptor = try UploadChunkDescriptor(range: range, content: content)
        let source = ManagedUploadSourceIdentity(id: sourceID, directoryDevice: 1, directoryInode: 2,
            file: .init(device: 1, inode: 3, size: Int64(range.length), modifiedSeconds: 1, modifiedNanoseconds: 0,
                changedSeconds: 1, changedNanoseconds: 0), content: content)
        let chunk = try ManagedUploadChunkIdentity(source: source, descriptor: descriptor)
        let intent = BackgroundMediaTaskIntent(id: taskID, context: context,
            session: session,
            taskDescription: UUID().uuidString, requestFingerprint: .init(sha256: String(repeating: "c", count: 64)),
            source: .uploadChunk(lease: acquired.lease, chunk: chunk, metadata: selected))
        let identifier = try await mediaSnapshot(store).backgroundTasks.count + 1
        return .init(intent: intent, lease: acquired.lease, chunk: chunk, acquisition: acquired.fact, sdkIdentifier: identifier)
    }
    fileprivate func finish(_ attempt: ChunkStoreAttempt, order: String = "normal") async throws -> ChunkStoreStopped {
        _ = try await event(.attached(attempt.intent, attempt.binding))
        _ = try await event(.stopRequested(attempt.intent))
        _ = try await event(.terminal(attempt.intent, .init(binding: attempt.binding, outcome: .cancelled)))
        let release: OriginalStoreJournalEntry, stopped: BackendCommitReceipt
        if order == "release-before-close" {
            release = try await originalChange(.release(attempt.lease))
            _ = try await event(.ownerClosed(attempt.intent, attempt.closure)); stopped = try await transition(.stopped(attempt.stop))
        } else if order == "stop-before-close" {
            stopped = try await transition(.stopped(attempt.stop))
            _ = try await event(.ownerClosed(attempt.intent, attempt.closure)); release = try await originalChange(.release(attempt.lease))
        } else {
            _ = try await event(.ownerClosed(attempt.intent, attempt.closure))
            if order == "stop-before-release" {
                stopped = try await transition(.stopped(attempt.stop)); release = try await originalChange(.release(attempt.lease))
            } else {
                release = try await originalChange(.release(attempt.lease)); stopped = try await transition(.stopped(attempt.stop))
            }
        }
        return .init(release: release, stopped: stopped)
    }
    fileprivate func document(originals: [OriginalStoreJournalEntry]) async throws -> RecordingStoreDocument {
        let inventory = try await self.inventory(), snapshot = try await mediaSnapshot(store)
        var document = RecordingStoreDocument()
        document.storeIdentity = source.storeIdentity; document.transactionRevision = snapshot.revision; document.entries = [recording]
        document.originalJournal = ([bindingFact] + originals).sorted { $0.receipt.committedRevision < $1.receipt.committedRevision }
        document.backendJournal = inventory.journal.map { .init(mutation: $0.mutation, receipt: $0.commit) }
        try document.validate()
        return document
    }
    fileprivate func reserveRemoval() async throws {
        let target = OriginalRemovalTarget(original: source.original, reference: original.reference, operation: .init(rawValue: UUID().uuidString))
        let batch = try OriginalRemovalBatch(operation: .init(rawValue: UUID().uuidString), purpose: .discard, targets: [target],
            authorization: .discardRiskAcknowledged(target))
        _ = try await originalChange(.removalBatch(batch), operation: batch.operation)
        let state = try #require(try await mediaOriginalSnapshot(store).logicalOriginals.first)
        let intent = batch.intent(for: target)
        _ = try await originalChange(.reserveRemoval(intent, expectedInvalidation: state.invalidationGeneration,
            expectedAccess: state.accessGeneration), operation: target.operation)
        let reserved = try await mediaOriginalSnapshot(store)
        #expect(reserved.logicalOriginals.first?.removal == intent)
        #expect(reserved.removalBatches.last?.targets.first?.status == .reserved(intent))
    }
}

nonisolated fileprivate struct ChunkStoreAttempt {
    let intent: BackgroundMediaTaskIntent
    let lease: OriginalReadLease
    let chunk: ManagedUploadChunkIdentity
    let acquisition: OriginalStoreJournalEntry
    var sdkIdentifier = 17
    var binding: BackgroundMediaTaskBinding { .init(session: intent.session, taskIdentifier: sdkIdentifier, taskDescription: intent.taskDescription) }
    var closure: BackgroundMediaOwnerClosure { .init(binding: binding, uploadSource: intent.source.uploadOwnership?.source, tasksJoined: true, handlesClosed: true) }
    var stop: TransportStopReceipt { .init(operation: intent.context.operation, attempt: intent.context.attempt,
        target: intent.context.target, registration: intent.context.registration) }
}
nonisolated fileprivate struct ChunkStoreStopped {
    let release: OriginalStoreJournalEntry
    let stopped: BackendCommitReceipt
}
nonisolated private func chunkStoreIntent(_ intent: BackgroundMediaTaskIntent, source: BackgroundMediaTaskSource) -> BackgroundMediaTaskIntent {
    .init(id: intent.id, context: intent.context, session: intent.session, taskDescription: intent.taskDescription,
        requestFingerprint: intent.requestFingerprint, source: source)
}
nonisolated private func chunkStoreIsRejected(_ result: BackendCommitResult) -> Bool {
    if case .rejected = result { return true }; return false
}
nonisolated private func chunkStoreChangedSelection(_ selection: UploadChunkMetadataSelection, field: String) throws -> UploadChunkMetadataSelection {
    var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(selection)) as? [String: Any])
    switch field {
    case "uuid": object["storeIdentity"] = ["rawValue": UUID().uuidString]
    case "query": object["queryID"] = ["rawValue": "uncommitted-query"]
    case "fingerprint": object["observationFingerprint"] = String(repeating: "f", count: 64)
    case "generation": object["observationGeneration"] = ["rawValue": selection.observationGeneration.rawValue + 1]
    default: object["previousRevision"] = selection.previousRevision + 1; object["committedRevision"] = selection.committedRevision + 1
    }
    return try JSONDecoder().decode(UploadChunkMetadataSelection.self, from: JSONSerialization.data(withJSONObject: object))
}

private actor ChunkStoreRecoverySession: BackgroundMediaSessionPort {
    let observations: [BackgroundMediaTaskObservation]
    private(set) var otherCalls = 0
    private init(_ observations: [BackgroundMediaTaskObservation]) { self.observations = observations }
    nonisolated static func make(_ observations: [BackgroundMediaTaskObservation]) -> ChunkStoreRecoverySession { .init(observations) }
    func enumerate() async -> BackendOutcome<[BackgroundMediaTaskObservation]> { .succeeded(observations) }
    func events() async throws -> AsyncStream<BackgroundMediaSDKEvent> {
        otherCalls += 1; return AsyncStream { $0.finish() }
    }
    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest,
        upload: BackgroundMediaUploadFile?) async -> BackendOutcome<BackgroundMediaTaskBinding> { otherCalls += 1; return .notExecuted }
    func resume(_ binding: BackgroundMediaTaskBinding, permit: BackgroundMediaStrictPermit,
        captureAuthorization: CaptureMediaResumeAuthorization) async -> BackendOutcome<BackgroundMediaTaskBinding> { otherCalls += 1; return .notExecuted }
    func requestStop(_ binding: BackgroundMediaTaskBinding) async { otherCalls += 1 }
    func observeTerminal(_ binding: BackgroundMediaTaskBinding) async -> BackendOutcome<BackgroundMediaSDKTerminal> { otherCalls += 1; return .unknown }
    func invalidate() async { otherCalls += 1 }
}
