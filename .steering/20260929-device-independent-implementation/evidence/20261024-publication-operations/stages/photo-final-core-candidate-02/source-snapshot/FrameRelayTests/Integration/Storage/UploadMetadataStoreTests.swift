import Foundation
import os
import Testing
@testable import FrameRelay

/// Isolated real disks/MOVs; metadata replies and dispatch callbacks are explicit
/// test inputs. No HTTP, media sender, PhotoKit, credential or old fixture is used.
struct UploadMetadataStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func createAndCompletedGetAtomicallyAdoptOnlyTheActualObservationAuthority(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate)
            let created = try await f.createSession()
            var snapshot = try await mediaSnapshot(f.store)
            #expect(created.verification == nil && snapshot.verifications.isEmpty)
            #expect(snapshot.requests[0].session == f.binding().session && snapshot.requests[0].remote == .unknown)
            #expect(!snapshot.requests[0].hasReconciled && !snapshot.requests[0].canRun)
            let query = try await f.begin(.lookup(f.binding().session))
            let before = try await mediaSnapshot(f.store)
            let observed = try await f.observe(query, .status(f.status(.completed, evidence: f.proof())))
            snapshot = try await mediaSnapshot(f.store)
            let verification = try #require(snapshot.verifications.first)
            #expect(observed.isCommitted && observed.commit.previousRevision == before.revision
                && snapshot.revision == before.revision + 1)
            #expect(verification == observed.verification && verification.isCommitted && verification.commit == observed.commit)
            #expect(verification.key == observed.observation.key && verification.command == observed.observation.command)
            #expect(verification.key != .verification(verification.command, verification.evidence.id, verification.expected))
            #expect(snapshot.requests[0].remote == .succeeded(f.proof().id) && !snapshot.requests[0].canRun)
            #expect(snapshot.requests[0].transport == .queued && snapshot.requests[0].attempt == nil)
            #expect(snapshot.backgroundTasks.isEmpty && snapshot.outbox.isEmpty && snapshot.batches.isEmpty)
            let originals = try await mediaOriginalSnapshot(f.store)
            #expect(originals.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
            guard case .succeeded(let inventory) = await f.store.loadRemovalTransportInventory(f.source.original) else {
                throw BackendContractError.unavailable
            }
            #expect(inventory.journal.contains { UploadMetadataValidation.exact($0.mutation, query.mutation) })
            #expect(inventory.journal.contains { UploadMetadataValidation.exact($0.mutation, observed.mutation) })
            #expect(!inventory.journal.contains { if case .verification = $0.mutation.change { return true }; return false })
            #expect(!OriginalRemovalTransportHistory.neverStartedForRemoval(f.source.original, backend: snapshot))
            let reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == snapshot)
            #expect(await reopened.lookupCommit(query.mutation) == .committed(query.commit))
            #expect(await reopened.lookupCommit(observed.mutation) == .committed(observed.commit))
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func newReservationBlocksAnOldAttemptPermitAndOnlyItsLatestReplyClearsPending(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate)
            _ = try await f.createSession()
            let first = try await f.begin(.lookup(f.binding().session))
            let previous = try await f.observe(first, .status(f.status(.receiving)))
            #expect(try await mediaSnapshot(f.store).requests[0].canRun)
            let late = try await f.begin(.lookup(f.binding().session))
            var snapshot = try await mediaSnapshot(f.store)
            #expect(!snapshot.requests[0].canRun && snapshot.requests[0].uploadMetadataPending == late.query.generation)
            let attempt = try await f.transitionMutation(.beginAttempt(.init(rawValue: UUID().uuidString)))
            #expect(await f.store.commit(attempt) == .rejected(.wrongStage))
            // Exact old lookup is still valid; it cannot project the event again.
            #expect(await f.store.commit(previous.mutation) == .committed(previous.commit))
            let latest = try await f.begin(.lookup(f.binding().session))
            let oldReply = try UploadMetadataObservation(command: late.query.observationCommand, query: late, response: .status(f.status(.receiving)))
            #expect(await f.store.commit(try await f.mutation(.uploadMetadata(.observe(oldReply)))) == .rejected(.staleGeneration))
            // Even an old producer writing a later scalar reconciliation cannot
            // clear the metadata reservation or restore an attempt permit.
            _ = try await f.transition(.reconciled(.init(context: f.context, observation: late.query.generation, result: .notExecuted)))
            snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.requests[0].hasReconciled && !snapshot.requests[0].canRun)
            _ = try await f.observe(latest, .status(f.status(.finalizing)))
            #expect(try await mediaSnapshot(f.store).requests[0].canRun)
            _ = try await f.transition(.beginAttempt(.init(rawValue: UUID().uuidString)))
            snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.requests[0].transport == .active && snapshot.backgroundTasks.isEmpty)
            #expect(snapshot.uploadMetadataQueries.map { $0.query.generation.rawValue } == [1, 2, 3, 4])
            let reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == snapshot)
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func anInterveningPersonInstructionBlocksPostButAllowsItsReplyAndKnownSessionGet(candidate: StorageCandidate, cancel: Bool) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate), query = try await f.begin(.create)
            _ = try await f.transition(.wait(.saving, active: true))
            try await f.person(cancel ? .cancel : .pause)
            let counter = MetadataDispatchCounter()
            #expect(!(await f.store.performUploadMetadataIfCurrent(query) { counter.increment() }))
            #expect(counter.value == 0)
            let forbidden = try await f.proposal(.create)
            #expect(await f.store.commit(try await f.mutation(.uploadMetadata(.beginQuery(forbidden)))) == .rejected(.wrongStage))
            _ = try await f.observe(query, .created(f.binding()))
            let lookup = try await f.begin(.lookup(f.binding().session))
            #expect(await f.store.performUploadMetadataIfCurrent(lookup) { counter.increment() })
            let record = try await f.observe(lookup, .status(f.status(.failed, failure: "technical-finalize-failure")))
            let after = try await mediaSnapshot(f.store)
            #expect(counter.value == 1 && after.requests[0].intent == (cancel ? .cancelled : .paused))
            #expect(after.requests[0].waits == [.saving] && after.requests[0].remote == .failed(.rejected))
            #expect(!after.requests[0].canRun && after.verifications.isEmpty)
            guard case .status(let status) = record.observation.response else { throw BackendContractError.invalidValue }
            #expect(status.failureCode == "technical-finalize-failure" && status.state == .failed)
            #expect(try await mediaSnapshot(f.reopen()) == after)
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func externalCancellationIsTypedAndCannotBeReinterpretedAsNotExecuted(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate)
            _ = try await f.createSession()
            _ = try await f.transition(.wait(.wiFiUnavailable, active: true))
            let query = try await f.begin(.lookup(f.binding().session))
            let record = try await f.observe(query, .status(f.status(.cancelled)))
            var snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.requests[0].intent == .running && snapshot.requests[0].waits == [.wiFiUnavailable])
            #expect(snapshot.requests[0].remote == .unknown && snapshot.requests[0].uploadMetadataHold == .serverCancelled)
            #expect(snapshot.requests[0].transport == .queued && snapshot.verifications.isEmpty && record.verification == nil)
            _ = try await f.transition(.wait(.wiFiUnavailable, active: false))
            _ = try await f.transition(.reconciled(.init(context: f.context, observation: .init(rawValue: 3), result: .notExecuted)))
            #expect(!(try await mediaSnapshot(f.store).requests[0].canRun))
            #expect(await f.store.commit(try await f.transitionMutation(.beginAttempt(.init(rawValue: UUID().uuidString)))) == .rejected(.wrongStage))
            let next = try await f.begin(.lookup(f.binding().session))
            #expect(next.query.generation.rawValue == 4)
            let counter = MetadataDispatchCounter()
            #expect(await f.store.performUploadMetadataIfCurrent(next) { counter.increment() })
            _ = try await f.observe(next, .status(f.status(.receiving)))
            snapshot = try await mediaSnapshot(f.store)
            #expect(counter.value == 1 && snapshot.requests[0].uploadMetadataHold == .serverCancelled && !snapshot.requests[0].canRun)
            #expect(try await mediaSnapshot(f.reopen()) == snapshot)
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func overflowAndChangedImmutableScopesNeverReserveOrBorrowQueries(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate, operation: .init(rawValue: "upload-\u{00e9}"))
            for field in ["uuid", "operation-alias", "original", "start-revision", "registration-receipt"] {
                let source = try metadataChangedSource(f.source, field: field)
                let query = try UploadMetadataQuery(id: .init(rawValue: UUID().uuidString), observationCommand: .init(rawValue: UUID().uuidString),
                    request: source, kind: .create, generation: .init(rawValue: 1))
                #expect(await f.store.commit(try await f.mutation(.uploadMetadata(.beginQuery(query)), identity: source.storeIdentity)) == .rejected(.identityMismatch))
            }
            let valid = try await f.proposal(.create)
            let mutation = try await f.mutation(.uploadMetadata(.beginQuery(valid)))
            #expect(await f.store.commit(.init(expectedRevision: mutation.expectedRevision, change: mutation.change)) == .rejected(.identityMismatch))
            #expect(try await mediaSnapshot(f.store).uploadMetadataQueries.isEmpty)
            _ = try await f.transition(.reconciled(.init(context: .init(operation: f.source.operation, registration: f.source.registration.server.registration,
                target: .original(f.source.original), session: nil), observation: .init(rawValue: UInt64.max), result: .notExecuted)))
            let oldGeneration = try UploadMetadataQuery(id: .init(rawValue: UUID().uuidString), observationCommand: .init(rawValue: UUID().uuidString),
                request: f.source, kind: .create, generation: .init(rawValue: UInt64.max))
            #expect(await f.store.commit(try await f.mutation(.uploadMetadata(.beginQuery(oldGeneration)))) == .rejected(.staleGeneration))
            #expect(try await mediaSnapshot(f.store).uploadMetadataQueries.isEmpty)
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["begin-before", "begin-after", "observe-before", "observe-after"])
    func lostDiskResponsesRetainExactOriginalEnvelopesAndReopenWithoutResubmission(candidate: StorageCandidate, scenario: String) async throws {
        try await withStorageRun { run in
            let phase = scenario.hasPrefix("begin") ? "begin" : "observe", afterCommit = scenario.hasSuffix("after")
            let id = MediaOperationID(rawValue: "query-\u{00e9}"), command = MediaOperationID(rawValue: "observation-\u{00e9}")
            let identity: BackendCommitIdentity = phase == "begin" ? .uploadMetadataQuery(id) : .uploadMetadataObservation(command)
            let fault: RecordingStoreFault = afterCommit ? .afterBackendCommitBeforeReply(identity) : .beforeBackendCommit(identity)
            let f = try await MetadataDiskFixture.make(run, candidate: candidate, fault: fault)
            let query = try await f.proposal(.create, id: id, observationCommand: command)
            let mutation: BackendStoreMutation
            if phase == "begin" { mutation = try await f.mutation(.uploadMetadata(.beginQuery(query))) }
            else {
                let committed = try await f.commitQuery(query)
                let observation = try UploadMetadataObservation(command: command, query: committed, response: .created(f.binding()))
                mutation = try await f.mutation(.uploadMetadata(.observe(observation)))
            }
            #expect(await f.store.commit(mutation) == (afterCommit ? .unknown : .unavailable(.inaccessible)))
            let reopened = try f.reopen(), snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.uploadMetadataObservations.count == (phase == "observe" && afterCommit ? 1 : 0))
            if afterCommit {
                let receipt: BackendCommitReceipt
                if phase == "begin" {
                    let stored = try #require(snapshot.uploadMetadataQueries.first)
                    #expect(UploadMetadataValidation.exact(stored.mutation, mutation)); receipt = stored.commit
                } else {
                    let stored = try #require(snapshot.uploadMetadataObservations.first)
                    #expect(UploadMetadataValidation.exact(stored.mutation, mutation)); receipt = stored.commit
                }
                #expect(await reopened.lookupCommit(mutation) == .committed(receipt))
                #expect(await reopened.lookupCommit(.init(expectedRevision: mutation.expectedRevision + 1, change: mutation.change,
                    expectedStoreIdentity: f.source.storeIdentity)) == .rejected(.identityMismatch))
            } else { #expect(await reopened.lookupCommit(mutation) == .unknown) }
            #expect(try await mediaSnapshot(reopened) == snapshot)
            #expect(snapshot.backgroundTasks.isEmpty && snapshot.verifications.isEmpty)
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func dispatchAndPersonPauseAreOrderedByTheSameDiskWriter(candidate: StorageCandidate, pauseFirst: Bool) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate), query = try await f.begin(.create)
            let other = try f.reopen(), counter = MetadataDispatchCounter()
            if pauseFirst {
                try await f.person(.pause, store: other)
                #expect(!(await f.store.performUploadMetadataIfCurrent(query) { counter.increment() }))
                #expect(counter.value == 0)
            } else {
                #expect(await f.store.performUploadMetadataIfCurrent(query) { counter.increment() })
                try await f.person(.pause, store: other)
                #expect(counter.value == 1)
            }
            #expect(!(await other.performUploadMetadataIfCurrent(query) { counter.increment() }))
            #expect(counter.value == (pauseFirst ? 0 : 1))
            let snapshot = try await mediaSnapshot(other)
            #expect(snapshot.requests[0].intent == .paused && snapshot.requests[0].uploadMetadataPending == query.query.generation)
            #expect(snapshot.requests[0].transport == .queued && snapshot.backgroundTasks.isEmpty)
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func dispatchRejectsUncommittedObservedSupersededAndChangedRegistrationScopes(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate), first = try await f.begin(.create)
            let counter = MetadataDispatchCounter()
            let falseReceipt = CommittedUploadMetadataQuery(query: first.query,
                commit: .init(key: first.query.key, previousRevision: first.commit.previousRevision + 1,
                    committedRevision: first.commit.committedRevision + 1), expectedStoreIdentity: first.expectedStoreIdentity)
            #expect(!(await f.store.performUploadMetadataIfCurrent(falseReceipt) { counter.increment() }))
            let wrongUUID = CommittedUploadMetadataQuery(query: first.query, commit: first.commit, expectedStoreIdentity: .init(rawValue: UUID()))
            #expect(!(await f.store.performUploadMetadataIfCurrent(wrongUUID) { counter.increment() }))
            let latest = try await f.begin(.create)
            #expect(!(await f.store.performUploadMetadataIfCurrent(first) { counter.increment() }))
            #expect(await f.store.performUploadMetadataIfCurrent(latest) { counter.increment() })
            _ = try await f.observe(latest, .created(f.binding()))
            #expect(!(await f.store.performUploadMetadataIfCurrent(latest) { counter.increment() }))
            let get = try await f.begin(.lookup(f.binding().session))
            let newer = RegistrationIdentity(destination: f.source.registration.server.registration.destination,
                id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2))
            _ = try await mediaRegister(f.store, registration: newer)
            #expect(!(await f.store.performUploadMetadataIfCurrent(get) { counter.increment() }))
            #expect(counter.value == 1)
            let response = try UploadMetadataObservation(command: get.query.observationCommand, query: get, response: .status(f.status(.receiving)))
            #expect(await f.store.commit(try await f.mutation(.uploadMetadata(.observe(response)))) == .rejected(.identityMismatch))
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func aRemovalOrInvalidationReservationAndAnUnimplementedPortCannotDispatchPost(candidate: StorageCandidate, invalidation: Bool) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate), query = try await f.begin(.create)
            let counter = MetadataDispatchCounter(), unavailable = MetadataDefaultDispatchStore(base: f.store)
            #expect(!(await unavailable.performUploadMetadataIfCurrent(query) { counter.increment() }))
            if invalidation { try await f.reserveInvalidation() } else { try await f.reserveRemoval() }
            #expect(!(await f.store.performUploadMetadataIfCurrent(query) { counter.increment() }))
            #expect(counter.value == 0)
            #expect(try await mediaSnapshot(f.store).uploadMetadataQueries == [query])
            // The removed-state predicate is checked on an isolated memory
            // projection only. No false deletion result is written to disk.
            let backend = try await mediaSnapshot(f.store), originals = try await mediaOriginalSnapshot(f.store)
            var projection = MediaStoreProjection()
            projection.requests = backend.requests; projection.originals = originals.logicalOriginals
            projection.originals[0].removal = nil; projection.originals[0].invalidation = nil
            projection.originals[0].removalResolution = .removed
            #expect(throws: BackendContractError.wrongStage) { try projection.requireUploadMetadataCreate(index: 0, source: f.source) }
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func theNewReceiptWorksWithExistingCleanupRulesWithoutProvingSDKTermination(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate)
            _ = try await f.createSession()
            let query = try await f.begin(.lookup(f.binding().session))
            let record = try await f.observe(query, .status(f.status(.completed, evidence: f.proof())))
            let rendition = statusRendition(f.source.original), registration = f.source.registration.server.registration
            _ = try await f.backend(.publication(mediaPublication(rendition, registration: registration)))
            let operation = MediaOperationID(rawValue: UUID().uuidString)
            // An explicit confirmation contract input, not a native playback
            // or formal Rec.709 producer. Only receipt integration is tested.
            let distribution = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
                commit: .init(key: .distribution(operation, rendition, registration), previousRevision: 0, committedRevision: 1))
            let token = try PlaybackToken(distribution: distribution, session: .init(rawValue: "technical-play"),
                invalidationGeneration: .init(rawValue: 0), observation: .played)
            _ = try await f.backend(.confirmation(.init(operation: .init(rawValue: UUID().uuidString), playback: token)))
            let snapshot = try await mediaSnapshot(f.store), state = try #require(snapshot.confirmationStates.first)
            let verification = try #require(record.verification)
            #expect(CleanupRules.evaluate(original: f.descriptor, lastVerification: verification, confirmation: state,
                supportedSchemas: ["fr-final-read-v1"]) == .eligible(f.source.original, state.generation))
            #expect(!OriginalRemovalTransportHistory.neverStartedForRemoval(f.source.original, backend: snapshot))
            #expect(OriginalRemovalTransportHistory.stoppedTasks(f.source.original, backend: snapshot) == nil)
            #expect(snapshot.requests[0].transport == .queued && snapshot.backgroundTasks.isEmpty)
            #expect(try await mediaSnapshot(f.reopen()).verifications == snapshot.verifications)
            try await f.assertBytes()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["person-before", "person-after", "upload-before", "upload-after", "legacy-before", "legacy-after", "photo-before", "photo-after"])
    func bothQueryCommandsAreReservedAgainstEveryFixedPlanAndLegacyNestedOperation(candidate: StorageCandidate, scenario: String) async throws {
        try await withStorageRun { run in
            let f = try await MetadataDiskFixture.make(run, candidate: candidate)
            let kind = String(try #require(scenario.split(separator: "-").first)), metadataFirst = scenario.hasSuffix("after")
            let other = try await f.otherRequest()
            let photo: MetadataPhotoFixture?
            if kind == "photo" { photo = try await MetadataPhotoFixture.make(f) } else { photo = nil }
            let parent = MediaOperationID(rawValue: "reserved-parent-\u{00e9}"), child = MediaOperationID(rawValue: "reserved-child-\u{00e9}")
            if metadataFirst {
                let query = try await f.proposal(.create, id: parent, observationCommand: child)
                let committed = try await f.commitQuery(query)
                let before = try await mediaSnapshot(f.store)
                for alias in ["reserved-parent-e\u{0301}", "reserved-child-e\u{0301}"] {
                    for parentCollision in [false, true] {
                        let change = try await f.planChange(kind, parent: .init(rawValue: parentCollision ? alias : UUID().uuidString),
                            child: .init(rawValue: parentCollision ? UUID().uuidString : alias), other: other, photo: photo)
                        #expect(await f.store.commit(try await f.mutation(change)) == .rejected(.identityMismatch))
                    }
                }
                #expect(try await mediaSnapshot(f.store) == before)
                _ = try await f.transition(.wait(.saving, active: true)) // Existing operation reference remains valid.
                _ = try await f.observe(committed, .created(f.binding()))
                #expect(try await mediaSnapshot(f.store).requests[0].waits == [.saving])
            } else {
                let change = try await f.planChange(kind, parent: parent, child: child, other: other, photo: photo)
                _ = try await f.backend(change)
                let before = try await mediaSnapshot(f.store)
                for alias in ["reserved-parent-e\u{0301}", "reserved-child-e\u{0301}"] {
                    for queryCollision in [false, true] {
                        let query = try await f.proposal(.create,
                            id: .init(rawValue: queryCollision ? alias : UUID().uuidString),
                            observationCommand: .init(rawValue: queryCollision ? UUID().uuidString : alias))
                        #expect(await f.store.commit(try await f.mutation(.uploadMetadata(.beginQuery(query)))) == .rejected(.identityMismatch))
                    }
                }
                #expect(try await mediaSnapshot(f.store) == before)
                _ = try await f.begin(.create)
            }
            let after = try await mediaSnapshot(f.store)
            #expect(after.uploadMetadataQueries.count == 1 && after.uploadMetadataObservations.count == (metadataFirst ? 1 : 0))
            #expect(try await mediaSnapshot(f.reopen()) == after)
            if let photo { #expect(try Data(contentsOf: photo.mediaURL) == photo.bytes) }
            try await f.assertBytes()
        }
    }
}

nonisolated private final class MetadataDispatchCounter: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private actor MetadataDefaultDispatchStore: MediaOperationStorePort {
    let base: any MediaOperationStorePort
    init(base: any MediaOperationStorePort) { self.base = base }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
}

nonisolated private struct MetadataDiskFixture {
    let originals: OriginalRemovalFixture
    let original: OriginalBinding
    let source: UploadMetadataRequest
    var store: any MediaDiskStore { originals.store }
    var context: RemoteOperationContext { .init(operation: source.operation, registration: source.registration.server.registration,
        target: .original(source.original), session: binding().session) }
    var descriptor: OriginalDescriptor { .init(original: original.original, reference: original.reference, saveResult: original.saveRecord.result,
        saveCommit: original.saveCommit, savedReference: original.reference, savedContext: original.saveRecord.intent.context,
        presence: .present, readiness: .ready) }

    static func make(_ run: ExplorationRunDirectory, candidate: StorageCandidate, fault: RecordingStoreFault? = nil,
        operation: MediaOperationID = .init(rawValue: UUID().uuidString.lowercased())) async throws -> Self {
        let store: any MediaDiskStore
        switch candidate {
        case .atomicFile: store = try AtomicFileRecordingStore(run: run, mode: .createNew, fault: fault, supportedVerificationSchemas: ["fr-final-read-v1"])
        case .sqlite: store = try SQLiteRecordingStore(run: run, mode: .createNew, fault: fault, supportedVerificationSchemas: ["fr-final-read-v1"])
        }
        let files = ManagedOriginalStore(run: run), access = ManagedOriginalAccess(store: store, originals: files)
        let originals = OriginalRemovalFixture(run: run, store: store, files: files, access: access, candidate: candidate)
        let binding = try await originals.original("metadata-" + UUID().uuidString)
        let registration = try await inventoryRegister(store)
        let snapshot = try await mediaSnapshot(store), identity = try #require(snapshot.storeIdentity)
        let request = try OriginalUploadAcceptanceRequest(parent: .init(rawValue: UUID().uuidString), storeIdentity: identity,
            registration: registration, scope: .single, targets: [.init(operation: operation, binding: binding)])
        let plan = try OriginalUploadAcceptancePlan(request: request, presences: [.present(byteCount: binding.original.content.byteCount)])
        guard case .committed = await store.commit(.init(expectedRevision: snapshot.revision, change: .originalUploadAcceptance(plan),
            expectedStoreIdentity: identity)) else { throw BackendContractError.notCommitted }
        let queued = try #require(try await mediaSnapshot(store).requests.first)
        return .init(originals: originals, original: binding,
            source: try .init(storeIdentity: identity, registration: registration, operation: operation,
                original: binding.original, expectedStartRevision: queued.expectedStartRevision))
    }
    func binding() -> UploadMetadataBinding { .init(registration: source.registration.server.registration, operation: source.operation,
        original: source.original, session: .init(rawValue: "d2dcdfac-6f18-433f-9f7b-7f2909bf9b10"), chunkSize: 65_536) }
    func status(_ state: UploadMetadataState, evidence: UploadFinalReadEvidence? = nil, indexes: [UInt64] = [], failure: String? = nil) -> UploadMetadataStatus {
        .init(binding: binding(), state: state, evidence: evidence, chunkIndexes: indexes, failureCode: failure)
    }
    func proof() -> UploadFinalReadEvidence { .init(id: .init(rawValue: "49069278-843e-448c-99f0-4ec714a3516a"), schemaVersion: "fr-final-read-v1",
        method: "final_destination_read_back", committed: true, finalSaveCompleted: true, sha256: source.original.content.digest,
        byteCount: source.original.content.byteCount, observedAt: Date(timeIntervalSince1970: 1_700_000_000)) }
    func proposal(_ kind: UploadMetadataQueryKind, id: MediaOperationID = .init(rawValue: UUID().uuidString),
        observationCommand: MediaOperationID = .init(rawValue: UUID().uuidString)) async throws -> UploadMetadataQuery {
        let snapshot = try await mediaSnapshot(store), request = try #require(snapshot.requests.first { $0.operation == source.operation })
        let generations = snapshot.uploadMetadataQueries.filter { $0.query.request.operation == source.operation }.map { $0.query.generation }
        return try .init(id: id, observationCommand: observationCommand, request: source, kind: kind,
            generation: UploadMetadataGeneration.next(lastObservation: request.lastObservation, reservations: generations))
    }
    func begin(_ kind: UploadMetadataQueryKind) async throws -> CommittedUploadMetadataQuery {
        let query = try await proposal(kind)
        return try await commitQuery(query)
    }
    func commitQuery(_ query: UploadMetadataQuery) async throws -> CommittedUploadMetadataQuery {
        let mutation = try await mutation(.uploadMetadata(.beginQuery(query)))
        guard case .committed(let receipt) = await store.commit(mutation) else { throw BackendContractError.notCommitted }
        let value = try #require(try await mediaSnapshot(store).uploadMetadataQueries.last)
        guard value.isCommitted, value.commit == receipt, UploadMetadataValidation.exact(value.mutation, mutation) else { throw BackendContractError.identityMismatch }
        return value
    }
    func createSession() async throws -> StoredUploadMetadataObservation {
        let query = try await begin(.create)
        return try await observe(query, .created(binding()))
    }
    func observe(_ query: CommittedUploadMetadataQuery, _ response: UploadMetadataResponse) async throws -> StoredUploadMetadataObservation {
        let observation = try UploadMetadataObservation(command: query.query.observationCommand, query: query, response: response)
        let mutation = try await mutation(.uploadMetadata(.observe(observation)))
        guard case .committed(let receipt) = await store.commit(mutation) else { throw BackendContractError.notCommitted }
        let value = try #require(try await mediaSnapshot(store).uploadMetadataObservations.last)
        guard value.isCommitted, value.commit == receipt, UploadMetadataValidation.exact(value.mutation, mutation) else { throw BackendContractError.identityMismatch }
        return value
    }
    func mutation(_ change: BackendStoreChange, identity: RegistrationStoreIdentity? = nil) async throws -> BackendStoreMutation {
        .init(expectedRevision: try await mediaSnapshot(store).revision, change: change, expectedStoreIdentity: identity ?? source.storeIdentity)
    }
    func backend(_ change: BackendStoreChange) async throws -> BackendCommitReceipt {
        guard case .committed(let receipt) = await store.commit(try await mutation(change)) else { throw BackendContractError.notCommitted }
        return receipt
    }
    func transitionMutation(_ value: MediaRequestTransition) async throws -> BackendStoreMutation {
        try await mutation(.requestTransition(command: .init(rawValue: UUID().uuidString), operation: source.operation,
            target: .original(source.original), registration: source.registration.server.registration, value: value))
    }
    func transition(_ value: MediaRequestTransition) async throws -> BackendCommitReceipt {
        guard case .committed(let receipt) = await store.commit(try await transitionMutation(value)) else { throw BackendContractError.notCommitted }
        return receipt
    }
    func person(_ action: MediaPersonControlAction, store override: (any MediaDiskStore)? = nil) async throws {
        let selected = override ?? store, snapshot = try await mediaSnapshot(selected)
        let request = try #require(snapshot.requests.first { $0.operation == source.operation })
        let plan = try MediaPersonControlPlan(parent: .init(rawValue: UUID().uuidString), storeIdentity: source.storeIdentity, scope: .single,
            action: action, children: [.init(command: .init(rawValue: UUID().uuidString), target: .init(request))])
        guard case .committed = await selected.commit(.init(expectedRevision: snapshot.revision, change: .personControl(plan),
            expectedStoreIdentity: source.storeIdentity)) else { throw BackendContractError.notCommitted }
    }
    func otherRequest() async throws -> MediaRequest {
        let request = MediaRequest(operation: .init(rawValue: UUID().uuidString), target: .original(source.original), purpose: .upload,
            registration: source.registration.server.registration, expectedStartRevision: try await mediaSnapshot(store).revision)
        _ = try await backend(.request(command: request.operation, value: request))
        return try #require(try await mediaSnapshot(store).requests.last)
    }
    func planChange(_ kind: String, parent: MediaOperationID, child: MediaOperationID, other: MediaRequest,
        photo: MetadataPhotoFixture?) async throws -> BackendStoreChange {
        switch kind {
        case "person":
            return .personControl(try .init(parent: parent, storeIdentity: source.storeIdentity, scope: .single, action: .pause,
                children: [.init(command: child, target: .init(other))]))
        case "upload":
            let request = try OriginalUploadAcceptanceRequest(parent: parent, storeIdentity: source.storeIdentity, registration: source.registration,
                scope: .single, targets: [.init(operation: child, binding: original)])
            return .originalUploadAcceptance(try .init(request: request, presences: [.missing]))
        case "legacy":
            let batch = try TransferBatch(id: .init(rawValue: parent.rawValue), originals: [descriptor], operations: [child], onWiFi: true,
                registration: source.registration, expectedRevision: try await mediaSnapshot(store).revision)
            return .batch(batch)
        case "photo":
            let photo = try #require(photo)
            let target = try PhotoSaveBatchTarget(source: photo.source, operation: child)
            let batch = try PhotoSaveBatch(operation: parent, storeIdentity: source.storeIdentity, targets: [target])
            return .photoBatch(command: parent, value: .accept(batch))
        default: throw BackendContractError.invalidValue
        }
    }
    func reserveRemoval() async throws {
        let batch = try originals.discardBatch(original, name: "metadata-removal-" + UUID().uuidString)
        let snapshot = try await mediaOriginalSnapshot(store)
        guard case .committed = await store.commitOriginal(.init(operation: batch.operation, expectedRevision: snapshot.revision,
            change: .removalBatch(batch))) else { throw BackendContractError.notCommitted }
        let current = try await mediaOriginalSnapshot(store)
        let state = try #require(current.logicalOriginals.first { UploadMetadataValidation.exact($0.original, source.original) })
        let intent = batch.intent(for: batch.targets[0])
        guard case .committed = await store.commitOriginal(.init(operation: intent.operation, expectedRevision: current.revision,
            change: .reserveRemoval(intent, expectedInvalidation: state.invalidationGeneration, expectedAccess: state.accessGeneration))) else {
            throw BackendContractError.notCommitted
        }
    }
    func reserveInvalidation() async throws {
        let rendition = statusRendition(source.original), registration = source.registration.server.registration
        _ = try await backend(.publication(mediaPublication(rendition, registration: registration)))
        _ = try await mediaOriginalCommit(store, .reserveInvalidation(.init(statusInvalidation(rendition, registration: registration,
            id: "new-metadata-invalidation-" + UUID().uuidString))))
    }
    func reopen() throws -> any MediaDiskStore {
        switch originals.candidate {
        case .atomicFile: try AtomicFileRecordingStore(run: originals.run, mode: .openExisting, supportedVerificationSchemas: ["fr-final-read-v1"])
        case .sqlite: try SQLiteRecordingStore(run: originals.run, mode: .openExisting, supportedVerificationSchemas: ["fr-final-read-v1"])
        }
    }
    func assertBytes() async throws {
        let digest = try await originals.files.digest(for: original.reference)
        #expect(digest.sha256 == source.original.content.digest && digest.byteCount == source.original.content.byteCount)
    }
}

nonisolated private struct MetadataPhotoFixture {
    let temporary: ManagedTemporaryMedia
    let scope: RenditionMediaScope
    let source: PhotoSaveSource
    let mediaURL: URL
    let bytes: Data
    static func make(_ f: MetadataDiskFixture) async throws -> Self {
        let bytes = Data((0..<1024).map { UInt8($0 % 251) }), content = try renditionContent(bytes)
        let registration = f.source.registration.server.registration
        let rendition = RenditionIdentity(original: f.source.original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "no-quality-proof",
            transformAssetVersion: "fixture-only", outputConfigurationIdentity: "fixture", conversionVersion: "fixture",
            rendition: .init(rawValue: UUID().uuidString.lowercased()), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
        _ = try await f.backend(.publication(mediaPublication(rendition, registration: registration)))
        let operation = MediaOperationID(rawValue: "technical-distribution-" + UUID().uuidString)
        let proof = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
            commit: .init(key: .distribution(operation, rendition, registration), previousRevision: 0, committedRevision: 1))
        let retrieve = RetrieveMediaCommand(gate: .init(operation: .init(rawValue: "technical-read"), attempt: .init(rawValue: "technical-attempt"),
            target: .rendition(rendition), registration: registration, generation: 1), distribution: proof, range: nil)
        let leases = RenditionReadLeases(store: f.store)
        let scope = try await RenditionMediaScope.open(original: f.source.original, leases: leases)
        let root = f.originals.run.url.appendingPathComponent("new-metadata-photo-" + UUID().uuidString, isDirectory: true)
        let temporary = try await ManagedTemporaryMedia.open(root: root, leases: leases, scope: scope)
        let receipt = try await temporary.create(command: retrieve, id: .init(rawValue: UUID().uuidString), usageID: .init(rawValue: UUID().uuidString),
            capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
        try await temporary.store(bytes, range: .init(lowerBound: 0, upperBound: UInt64(bytes.count)), using: receipt.usage)
        _ = try await temporary.verify(receipt.usage)
        let state = try await temporary.stateFor(receipt.id)
        let source = PhotoSaveSource(storeIdentity: f.source.storeIdentity, registration: registration, rendition: rendition, media: state.id,
            capturedAt: state.capturedAt, directoryIdentity: state.directoryIdentity, fileIdentity: try #require(state.fileIdentity), leaf: state.leaf,
            contentType: state.contentType)
        return .init(temporary: temporary, scope: scope, source: source, mediaURL: root.appendingPathComponent(state.leaf), bytes: bytes)
    }
}

nonisolated private func metadataChangedSource(_ source: UploadMetadataRequest, field: String) throws -> UploadMetadataRequest {
    let actual = source.registration
    let changedRegistration = DeviceRegistration(server: actual.server, intentCommit: actual.intentCommit,
        commit: .init(key: actual.commit.key, previousRevision: actual.commit.previousRevision + 1, committedRevision: actual.commit.committedRevision + 1))
    return try .init(storeIdentity: field == "uuid" ? .init(rawValue: UUID()) : source.storeIdentity,
        registration: field == "registration-receipt" ? changedRegistration : actual,
        operation: field == "operation-alias" ? .init(rawValue: "upload-e\u{0301}") : source.operation,
        original: field == "original" ? .init(capture: source.original.capture, generation: .init(rawValue: source.original.generation.rawValue + 1),
            content: source.original.content) : source.original,
        expectedStartRevision: source.expectedStartRevision + (field == "start-revision" ? 1 : 0))
}
