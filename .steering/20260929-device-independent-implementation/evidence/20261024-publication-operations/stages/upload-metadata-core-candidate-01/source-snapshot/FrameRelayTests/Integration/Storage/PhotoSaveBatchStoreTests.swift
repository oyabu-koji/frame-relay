import Foundation
import Testing
@testable import FrameRelay

/// New UUID-isolated roots exercise real disk/hash/use and the common writer.
/// Photos outcomes here are explicit journal inputs, never real PhotoKit or
/// formal rendition/quality evidence. No Photos SDK is invoked by this suite.
struct PhotoSaveBatchStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func fixedMultipleTargetsAreAtomicAndKeepTheirIndependentOutcomes(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let a = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate, capture: "first")
            let b = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate, capture: "second", existingStore: a.store)
            let first = try a.target("first-child"), second = try b.target("second-child")
            let operation = MediaOperationID(rawValue: "fixed-multiple")
            let wrong = try PhotoSaveBatchTarget(source: pbChangedSource(b.source, field: "file"), operation: second.operation)
            let invalid = try PhotoSaveBatch(operation: operation, storeIdentity: a.source.storeIdentity, targets: [first, wrong])
            #expect(await a.store.commit(try await pbMutation(a.store, command: operation, .accept(invalid)))
                == .rejected(.ineligibleOriginal))
            #expect(try await mediaSnapshot(a.store).photoSaveBatches.isEmpty)
            let batch = try PhotoSaveBatch(operation: operation, storeIdentity: a.source.storeIdentity, targets: [first, second])
            let accepted = try await pbMutation(a.store, command: operation, .accept(batch))
            _ = try await pbCommit(a.store, accepted)
            let subset = try PhotoSaveBatch(operation: operation, storeIdentity: a.source.storeIdentity, targets: [first])
            #expect(await a.store.lookupCommit(.init(expectedRevision: accepted.expectedRevision,
                change: .photoBatch(command: operation, value: .accept(subset)), expectedStoreIdentity: a.source.storeIdentity))
                == .rejected(.identityMismatch))
            _ = try await pbWrite(a.store, command: first.operation, .beginChild(batch: operation, target: first))
            let intent = try a.intent(first)
            _ = try await pbPhoto(a.store, command: first.operation, .intent(intent))
            _ = try await pbPhoto(a.store, command: .init(rawValue: "first-result"),
                .result(.init(intent: intent, outcome: .notAttempted(.authorizationRequired))))
            _ = try await pbWrite(a.store, command: second.operation,
                .notProcessed(batch: operation, target: second, reason: .cancelled))
            let reopened = try pbDisk(candidate, run: run, mode: .openExisting)
            let row = try #require(try await mediaSnapshot(reopened).photoSaveBatches.first)
            #expect(row.batch.targets == [first, second] && row.targets.map(\.target) == [first, second])
            #expect(row.targets[0].outcome == .notAttempted(.authorizationRequired))
            guard case .notProcessed = row.targets[1].status else { throw BackendContractError.wrongStage }
            #expect(row.targets[1].registration == nil && row.targets[1].outcome == nil)
            #expect(try await mediaSnapshot(reopened).photoRegistrations.count == 1)
            let firstBytes = try Data(contentsOf: a.mediaURL), secondBytes = try Data(contentsOf: b.mediaURL)
            #expect(firstBytes == a.bytes && secondBytes == b.bytes)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func acceptedChildJoinsOnlyTheExistingRegistrationOutcomeAcrossReopen(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate)
            let target = try f.target("child"), batch = try f.batch("batch", target)
            let before = try await mediaSnapshot(f.store)
            #expect(await f.store.commit(.init(expectedRevision: before.revision - 1,
                change: .photoBatch(command: batch.operation, value: .accept(batch)), expectedStoreIdentity: f.source.storeIdentity))
                == .rejected(.revisionConflict))
            #expect(await f.store.commit(.init(expectedRevision: before.revision,
                change: .photoBatch(command: batch.operation, value: .accept(batch)))) == .rejected(.identityMismatch))
            _ = try await pbWrite(f.store, command: batch.operation, .accept(batch))
            let accepted = try await mediaSnapshot(f.store)
            #expect(accepted.photoSaveBatches.first?.targets.first?.status == .queued)
            #expect(accepted.photoRegistrations.isEmpty && accepted.outbox == before.outbox)
            #expect(accepted.temporaryMedia == before.temporaryMedia)
            _ = try await pbWrite(f.store, command: target.operation, .beginChild(batch: batch.operation, target: target))
            let begun = try #require(try await mediaSnapshot(f.store).photoSaveBatches.first)
            guard case .starting(let start) = begun.targets[0].status else { throw BackendContractError.wrongStage }
            #expect(begun.isCommitted && start.isCommitted)
            #expect(await f.store.lookupCommit(start.mutation) == .committed(start.commit))
            let intent = try f.intent(target)
            _ = try await pbPhoto(f.store, command: target.operation, .intent(intent))
            _ = try await pbPhoto(f.store, command: .init(rawValue: "unknown"),
                .result(.init(intent: intent, outcome: .unknown(localIdentifier: nil))))
            #expect(try await mediaSnapshot(f.store).photoSaveBatches[0].targets[0].outcome == .unknown(localIdentifier: nil))
            _ = try await pbPhoto(f.store, command: .init(rawValue: "terminal"),
                .result(.init(intent: intent, outcome: .succeeded(localIdentifier: nil))))
            let reopened = try pbDisk(candidate, run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            let child = try #require(snapshot.photoSaveBatches.first?.targets.first)
            #expect(child.registration == snapshot.photoRegistrations.first)
            #expect(child.outcome == .succeeded(localIdentifier: nil))
            #expect(snapshot.photoRegistrations.count == 1 && snapshot.outbox == before.outbox)
            #expect(await reopened.lookupCommit(begun.mutation) == .committed(begun.commit))
            #expect(await reopened.lookupCommit(start.mutation) == .committed(start.commit))
            #expect(try Data(contentsOf: f.mediaURL) == f.bytes)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func batchAndStandaloneReserveTheSameKeyInBothOrders(candidate: StorageCandidate, standaloneFirst: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate)
            let target = try f.target("child"), batch = try f.batch("batch", target)
            let standalone = try f.intent(f.target("standalone"))
            if standaloneFirst {
                _ = try await pbPhoto(f.store, command: standalone.operation, .intent(standalone))
                #expect(await f.store.commit(try await pbMutation(f.store, command: batch.operation, .accept(batch)))
                    == .rejected(.duplicateTarget))
                #expect(try await mediaSnapshot(f.store).photoSaveBatches.isEmpty)
            } else {
                _ = try await pbWrite(f.store, command: batch.operation, .accept(batch))
                #expect(await f.store.commit(try await pbPhotoMutation(f.store, command: standalone.operation, .intent(standalone)))
                    == .rejected(.duplicateTarget))
                let own = try f.intent(target)
                #expect(await f.store.commit(try await pbPhotoMutation(f.store, command: own.operation, .intent(own)))
                    == .rejected(.identityMismatch))
                let competing = try f.batch("other-batch", f.target("other-child"))
                #expect(await f.store.commit(try await pbMutation(f.store, command: competing.operation, .accept(competing)))
                    == .rejected(.duplicateTarget))
                _ = try await pbWrite(f.store, command: target.operation,
                    .notProcessed(batch: batch.operation, target: target, reason: .cancelled))
                _ = try await pbPhoto(f.store, command: standalone.operation, .intent(standalone))
                let record = try #require(try await mediaSnapshot(f.store).photoSaveBatches.first)
                guard case .notProcessed(let cancelled) = record.targets[0].status else { throw BackendContractError.wrongStage }
                #expect(await f.store.lookupCommit(cancelled.mutation) == .committed(cancelled.commit))
                #expect(record.targets[0].registration == nil && record.targets[0].outcome == nil)
            }
            #expect(try await mediaSnapshot(f.store).photoRegistrations.count == 1)
            #expect(try Data(contentsOf: f.mediaURL) == f.bytes)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func startingWithoutIntentCannotBeCancelledOrTurnedBackIntoQueued(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate)
            let target = try f.target("child"), batch = try f.batch("batch", target)
            _ = try await pbWrite(f.store, command: batch.operation, .accept(batch))
            let mutation = try await pbMutation(f.store, command: target.operation, .beginChild(batch: batch.operation, target: target))
            let receipt = try await pbCommit(f.store, mutation)
            let reopened = try pbDisk(candidate, run: run, mode: .openExisting)
            #expect(await reopened.lookupCommit(mutation) == .committed(receipt))
            #expect(await reopened.commit(try await pbMutation(reopened, command: target.operation,
                .notProcessed(batch: batch.operation, target: target, reason: .cancelled))) == .rejected(.identityMismatch))
            #expect(await reopened.commit(try await pbMutation(reopened, command: .init(rawValue: "new-cancel-command"),
                .notProcessed(batch: batch.operation, target: target, reason: .cancelled))) == .rejected(.wrongStage))
            let retry = try f.batch("retry-batch", f.target("retry-child", retryOf: target.operation))
            #expect(await reopened.commit(try await pbMutation(reopened, command: retry.operation, .accept(retry)))
                == .rejected(.identityMismatch))
            let child = try #require(try await mediaSnapshot(reopened).photoSaveBatches.first?.targets.first)
            guard case .starting = child.status else { throw BackendContractError.wrongStage }
            #expect(child.registration == nil && child.outcome == nil)
            #expect(try await mediaSnapshot(reopened).photoRegistrations.isEmpty)
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["failed", "notAttempted", "unknown", "success", "intent", "notFound"])
    func retryNeedsTheLatestKnownNonAdditionAndExactSource(candidate: StorageCandidate, result: String) async throws {
        try await withStorageRun { run in
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate)
            let initial = try f.intent(f.target("standalone"))
            _ = try await pbPhoto(f.store, command: initial.operation, .intent(initial))
            let identifier = try PhotoAssetIdentifier(rawValue: "explicit-technical-asset")
            let outcome: PhotoRegistrationOutcome?
            switch result {
            case "failed": outcome = .failed(.invalidMedia)
            case "notAttempted": outcome = .notAttempted(.authorizationRequired)
            case "unknown": outcome = .unknown(localIdentifier: identifier)
            case "intent": outcome = nil
            default: outcome = .succeeded(localIdentifier: identifier)
            }
            if let outcome { _ = try await pbPhoto(f.store, command: .init(rawValue: "result"), .result(.init(intent: initial, outcome: outcome))) }
            if result == "notFound" {
                let observation = try PhotoPresenceObservation(intent: initial, generation: 1, identifier: identifier,
                    authorization: .authorized, presence: .notFound)
                _ = try await pbPhoto(f.store, command: .init(rawValue: "presence"), .presence(observation))
            }
            let target = try f.target("retry", retryOf: initial.operation), batch = try f.batch("batch", target)
            let mutation = try await pbMutation(f.store, command: batch.operation, .accept(batch))
            if result == "failed" || result == "notAttempted" {
                _ = try await pbCommit(f.store, mutation)
                _ = try await pbWrite(f.store, command: target.operation, .beginChild(batch: batch.operation, target: target))
                let retry = try await f.freshIntent(target)
                _ = try await pbPhoto(f.store, command: retry.operation, .intent(retry))
                let snapshot = try await mediaSnapshot(f.store)
                #expect(snapshot.photoRegistrations.count == 2)
                #expect(snapshot.photoSaveBatches[0].targets[0].registration?.registration.intent == retry)
                #expect(snapshot.photoSaveBatches[0].targets[0].outcome == nil)
                #expect(await f.store.commit(try await pbPhotoMutation(f.store, command: .init(rawValue: "late-old-success"),
                    .result(.init(intent: initial, outcome: .succeeded(localIdentifier: identifier))))) == .rejected(.wrongStage))
            } else {
                #expect(await f.store.commit(mutation) == .rejected(.duplicateTarget))
                #expect(try await mediaSnapshot(f.store).photoSaveBatches.isEmpty)
            }
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["file", "directory", "date", "media", "leaf", "mime", "rendition", "registration", "store"])
    func fixedSourceCannotBeSubstitutedAtAcceptanceOrChildStart(candidate: StorageCandidate, field: String) async throws {
        try await withStorageRun { run in
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate)
            let badSource = pbChangedSource(f.source, field: field)
            let bad = try PhotoSaveBatchTarget(source: badSource, operation: .init(rawValue: "bad"))
            let badBatch = try PhotoSaveBatch(operation: .init(rawValue: "bad-batch"), storeIdentity: badSource.storeIdentity, targets: [bad])
            let rejection = await f.store.commit(try await pbMutation(f.store, command: badBatch.operation, .accept(badBatch)))
            guard case .rejected = rejection else { throw BackendContractError.notCommitted }
            let target = try f.target("child"), batch = try f.batch("batch", target)
            _ = try await pbWrite(f.store, command: batch.operation, .accept(batch))
            let changed = try PhotoSaveBatchTarget(source: badSource, operation: target.operation)
            #expect(await f.store.commit(try await pbMutation(f.store, command: target.operation,
                .beginChild(batch: batch.operation, target: changed))) == .rejected(.identityMismatch))
            #expect(try await mediaSnapshot(f.store).photoSaveBatches[0].targets[0].status == .queued)
            #expect(try await mediaSnapshot(f.store).photoRegistrations.isEmpty)
            #expect(try Data(contentsOf: f.mediaURL) == f.bytes)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func failedBatchChildNeedsANewAcceptedRetryAndCannotLoanItsReservedCommand(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate)
            let target = try f.target("child"), batch = try f.batch("batch", target)
            _ = try await pbWrite(f.store, command: batch.operation, .accept(batch))
            _ = try await pbWrite(f.store, command: target.operation, .beginChild(batch: batch.operation, target: target))
            let intent = try f.intent(target)
            _ = try await pbPhoto(f.store, command: target.operation, .intent(intent))
            _ = try await pbPhoto(f.store, command: .init(rawValue: "non-addition"),
                .result(.init(intent: intent, outcome: .notAttempted(.restricted))))
            let retryTarget = try f.target("retry-child", retryOf: target.operation)
            let retryIntent = try f.intent(retryTarget)
            #expect(await f.store.commit(try await pbPhotoMutation(f.store, command: retryTarget.operation, .intent(retryIntent)))
                == .rejected(.duplicateTarget))
            let retry = try f.batch("retry-batch", retryTarget)
            _ = try await pbWrite(f.store, command: retry.operation, .accept(retry))
            // A callback for the old request cannot consume the reserved new
            // child's .photo command namespace before its own intent exists.
            #expect(await f.store.commit(try await pbPhotoMutation(f.store, command: retryTarget.operation,
                .result(.init(intent: intent, outcome: .notAttempted(.restricted))))) == .rejected(.identityMismatch))
            _ = try await pbWrite(f.store, command: retryTarget.operation, .beginChild(batch: retry.operation, target: retryTarget))
            let fresh = try await f.freshIntent(retryTarget)
            _ = try await pbPhoto(f.store, command: retryTarget.operation, .intent(fresh))
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.photoSaveBatches.count == 2 && snapshot.photoRegistrations.count == 2)
            #expect(snapshot.photoSaveBatches[0].targets[0].outcome == .notAttempted(.restricted))
            #expect(snapshot.photoSaveBatches[1].targets[0].registration?.registration.intent.operation == retryTarget.operation)
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["registration", "invalidation", "reclaimed", "partial", "unverified"])
    func writerRechecksLiveEligibilityInsteadOfTrustingAcceptedMetadata(candidate: StorageCandidate, change: String) async throws {
        try await withStorageRun { run in
            let incomplete = change == "partial" || change == "unverified"
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate, coverage: incomplete ? change : "complete")
            let target = try f.target("child"), batch = try f.batch("batch", target)
            if incomplete {
                #expect(await f.store.commit(try await pbMutation(f.store, command: batch.operation, .accept(batch)))
                    == .rejected(.ineligibleOriginal))
                return
            }
            _ = try await pbWrite(f.store, command: batch.operation, .accept(batch))
            switch change {
            case "registration":
                let old = f.source.registration
                _ = try await mediaRegister(f.store, registration: .init(destination: old.destination,
                    id: .init(rawValue: "replacement-registration"), generation: .init(rawValue: old.generation.rawValue + 1)))
            case "invalidation":
                let record = InvalidationRecord(id: .init(rawValue: "invalidate"), rendition: f.source.rendition,
                    registration: f.source.registration, generation: .init(rawValue: 1))
                _ = try await mediaOriginalCommit(f.store, .reserveInvalidation(.init(record)))
            default:
                #expect(await f.temporary.releaseUsage(f.receipt.usage) == .succeeded(f.receipt.id))
                #expect(try await mediaSnapshot(f.store).temporaryMedia.first?.reclaimed == true)
            }
            let result = await f.store.commit(try await pbMutation(f.store, command: target.operation,
                .beginChild(batch: batch.operation, target: target)))
            guard case .rejected = result else { throw BackendContractError.notCommitted }
            // A stale queued source can be cancelled, but cannot be replaced.
            _ = try await pbWrite(f.store, command: target.operation,
                .notProcessed(batch: batch.operation, target: target, reason: .ineligible))
            #expect(try await mediaSnapshot(f.store).photoRegistrations.isEmpty)
            if change != "reclaimed" { #expect(try Data(contentsOf: f.mediaURL) == f.bytes) }
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["accept-before", "accept-after", "begin-before", "begin-after", "cancel-before", "cancel-after"])
    func lostReplyUsesTheOriginalMutationAcrossUnrelatedCommitsAndReopen(candidate: StorageCandidate, stage: String) async throws {
        try await withStorageRun { run in
            let accept = stage.hasPrefix("accept"), begin = stage.hasPrefix("begin"), after = stage.hasSuffix("after")
            let command = MediaOperationID(rawValue: accept ? "batch" : "child")
            let fault: RecordingStoreFault = after ? .afterBackendCommitBeforeReply(.photoBatch(command)) : .beforeBackendCommit(.photoBatch(command))
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate, fault: fault)
            let target = try f.target("child"), batch = try f.batch("batch", target)
            if !accept { _ = try await pbWrite(f.store, command: batch.operation, .accept(batch)) }
            let change: PhotoSaveBatchChange = accept ? .accept(batch) : (begin
                ? .beginChild(batch: batch.operation, target: target)
                : .notProcessed(batch: batch.operation, target: target, reason: .cancelled))
            let mutation = try await pbMutation(f.store, command: command, change)
            #expect(await f.store.commit(mutation) == (after ? .unknown : .unavailable(.inaccessible)))
            let reopened = try pbDisk(candidate, run: run, mode: .openExisting)
            _ = try await mediaCommit(reopened, .registrationIntent(.init(operation: .init(rawValue: "unrelated"),
                destination: .init(rawValue: "independent-destination"))))
            if after {
                guard case .committed(let receipt) = await reopened.lookupCommit(mutation) else { throw BackendContractError.notCommitted }
                #expect(await reopened.commit(mutation) == .committed(receipt))
                #expect(await reopened.lookupCommit(.init(expectedRevision: mutation.expectedRevision + 1,
                    change: mutation.change, expectedStoreIdentity: mutation.expectedStoreIdentity)) == .rejected(.identityMismatch))
            } else { #expect(await reopened.lookupCommit(mutation) == .unknown) }
            #expect(try await mediaSnapshot(reopened).photoRegistrations.isEmpty)
            #expect(try Data(contentsOf: f.mediaURL) == f.bytes)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func byteDistinctSourceAndCommandCannotBorrowCommittedReceipts(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate, capture: "\u{e9}")
            let target = try f.target("child"), batch = try f.batch("\u{e9}", target)
            let mutation = try await pbMutation(f.store, command: batch.operation, .accept(batch))
            _ = try await pbCommit(f.store, mutation)
            let alias = try PhotoSaveBatch(operation: .init(rawValue: "e\u{301}"), storeIdentity: f.source.storeIdentity, targets: [target])
            let changedCommand = BackendStoreMutation(expectedRevision: mutation.expectedRevision,
                change: .photoBatch(command: alias.operation, value: .accept(alias)), expectedStoreIdentity: f.source.storeIdentity)
            #expect(mutation == changedCommand && !PhotoSaveBatchValueValidation.exact(mutation, changedCommand))
            #expect(await f.store.lookupCommit(changedCommand) == .rejected(.identityMismatch))
            #expect(await f.store.commit(changedCommand) == .rejected(.identityMismatch))
            let changedTarget = try PhotoSaveBatchTarget(source: pbChangedSource(f.source, field: "capture-alias"), operation: target.operation)
            #expect(target == changedTarget && !PhotoSaveBatchValueValidation.exact(target, changedTarget))
            #expect(await f.store.commit(try await pbMutation(f.store, command: target.operation,
                .beginChild(batch: batch.operation, target: changedTarget))) == .rejected(.identityMismatch))
            _ = try await pbWrite(f.store, command: target.operation, .beginChild(batch: batch.operation, target: target))
            let intent = try f.intent(target)
            let intentMutation = try await pbPhotoMutation(f.store, command: intent.operation, .intent(intent))
            _ = try await pbCommit(f.store, intentMutation)
            let aliasIntent = try PhotoRegistrationIntent(operation: target.operation,
                handoff: .init(media: intent.media, rendition: changedTarget.source.rendition,
                    capturedAt: intent.capturedAt, usage: intent.usage))
            let borrowed = BackendStoreMutation(expectedRevision: intentMutation.expectedRevision,
                change: .photo(command: intent.operation, value: .intent(aliasIntent)), expectedStoreIdentity: f.source.storeIdentity)
            #expect(intentMutation == borrowed && !PhotoSaveBatchValueValidation.exact(intentMutation, borrowed))
            #expect(await f.store.lookupCommit(borrowed) == .rejected(.identityMismatch))
            #expect(await f.store.commit(borrowed) == .rejected(.identityMismatch))
            #expect(await f.store.commit(try await pbPhotoMutation(f.store, command: .init(rawValue: "alias-result"),
                .result(.init(intent: aliasIntent, outcome: .succeeded(localIdentifier: nil))))) == .rejected(.identityMismatch))
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.photoSaveBatches[0].targets[0].outcome == nil && snapshot.photoRegistrations[0].outcome == nil)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func oldSchemaSevenStandaloneJournalKeepsItsOriginalMutationAndOutcomes(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoBatchDiskFixture.make(run: run, candidate: candidate)
            let intent = try f.intent(f.target("old-standalone"))
            let revision = try await mediaSnapshot(f.store).revision
            let legacy = BackendStoreMutation(expectedRevision: revision, change: .photo(command: intent.operation, value: .intent(intent)))
            let receipt = try await pbCommit(f.store, legacy)
            _ = try await pbPhoto(f.store, command: .init(rawValue: "old-result"), .result(.init(intent: intent, outcome: .notAttempted(.restricted))))
            let before = try await mediaSnapshot(f.store)
            let reopened = try pbDisk(candidate, run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot == before && snapshot.photoSaveBatches.isEmpty)
            #expect(snapshot.photoRegistrations.first?.outcome == .notAttempted(.restricted))
            #expect(await reopened.lookupCommit(legacy) == .committed(receipt))
            #expect(snapshot.photoRegistrations.first?.registration.mutation == legacy)
            if candidate == .atomicFile {
                let data = try Data(contentsOf: run.url.appendingPathComponent(candidate.fileName))
                let document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(document["schema"] as? Int == 7 && document["photoSaveBatches"] == nil)
            }
        }
    }
}

nonisolated private struct PhotoBatchDiskFixture: Sendable {
    let store: any MediaDiskStore
    let temporary: ManagedTemporaryMedia
    let scope: RenditionMediaScope
    let receipt: TemporaryMediaReceipt
    let source: PhotoSaveSource
    let mediaURL: URL
    let bytes: Data

    static func make(run: ExplorationRunDirectory, candidate: StorageCandidate, capture: String = "batch-fixture",
        coverage: String = "complete", fault: RecordingStoreFault? = nil, existingStore: (any MediaDiskStore)? = nil) async throws -> Self {
        let store: any MediaDiskStore
        if let existingStore { store = existingStore }
        else { store = try pbDisk(candidate, run: run, mode: .createNew, fault: fault) }
        let registration: RegistrationIdentity
        if let current = try await mediaSnapshot(store).registrations.last { registration = current.server.registration }
        else { registration = try await mediaRegister(store) }
        let snapshot = try await mediaSnapshot(store)
        let identity = try await store.establishRegistrationIdentity(expectedRevision: snapshot.revision, expectedIdentity: snapshot.storeIdentity)
        let bytes = Data((0..<1024).map { UInt8($0 % 251) }), content = try renditionContent(bytes)
        let original = OriginalContent(capture: .init(rawValue: capture), generation: .init(rawValue: 1), content: content)
        let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "no-quality-proof",
            transformAssetVersion: "fixture-only", outputConfigurationIdentity: "fixture", conversionVersion: "fixture",
            rendition: .init(rawValue: "fixture-rendition"), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
        let operation = MediaOperationID(rawValue: "technical-distribution-" + capture)
        let proof = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
            commit: .init(key: .distribution(operation, rendition, registration), previousRevision: 0, committedRevision: 1))
        let retrieve = RetrieveMediaCommand(gate: .init(operation: .init(rawValue: "read"), attempt: .init(rawValue: "attempt"),
            target: .rendition(rendition), registration: registration, generation: 1), distribution: proof, range: nil)
        let leases = RenditionReadLeases(store: store)
        let scope = try await RenditionMediaScope.open(original: original, leases: leases)
        let root = run.url.appendingPathComponent("new-batch-media-" + UUID().uuidString, isDirectory: true)
        let temporary = try await ManagedTemporaryMedia.open(root: root, leases: leases, scope: scope)
        let created = try await temporary.create(command: retrieve, id: .init(rawValue: "media-" + capture),
            usageID: .init(rawValue: "retrieval"), capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
        let stored = coverage == "partial" ? bytes.prefix(512) : bytes[...]
        try await temporary.store(Data(stored), range: .init(lowerBound: 0, upperBound: UInt64(stored.count)), using: created.usage)
        var receipt = try await temporary.stateFor(created.id).receipt(for: created.usage)
        if coverage == "complete" {
            _ = try await temporary.verify(created.usage)
            guard case .succeeded(let usage) = await temporary.acquireUsage(created.id, purpose: .photoHandoff,
                usageID: .init(rawValue: "photo")) else { throw BackendContractError.ineligibleOriginal }
            #expect(await temporary.releaseUsage(created.usage) == .succeeded(created.id))
            receipt = try await temporary.stateFor(created.id).receipt(for: usage)
        }
        let state = try await temporary.stateFor(created.id)
        let source = PhotoSaveSource(storeIdentity: identity, registration: registration, rendition: rendition,
            media: state.id, capturedAt: state.capturedAt, directoryIdentity: state.directoryIdentity,
            fileIdentity: try #require(state.fileIdentity), leaf: state.leaf, contentType: state.contentType)
        return .init(store: store, temporary: temporary, scope: scope, receipt: receipt, source: source,
            mediaURL: root.appendingPathComponent(state.leaf), bytes: bytes)
    }
    func target(_ operation: String, retryOf: MediaOperationID? = nil) throws -> PhotoSaveBatchTarget {
        try .init(source: source, operation: .init(rawValue: operation), retryOf: retryOf)
    }
    func batch(_ operation: String, _ target: PhotoSaveBatchTarget) throws -> PhotoSaveBatch {
        try .init(operation: .init(rawValue: operation), storeIdentity: source.storeIdentity, targets: [target])
    }
    func intent(_ target: PhotoSaveBatchTarget) throws -> PhotoRegistrationIntent {
        try .init(operation: target.operation, handoff: receipt.photoHandoff(expected: source.rendition), retryOf: target.retryOf)
    }
    func freshIntent(_ target: PhotoSaveBatchTarget) async throws -> PhotoRegistrationIntent {
        guard case .succeeded(let usage) = await temporary.acquireUsage(source.media, purpose: .photoHandoff,
            usageID: .init(rawValue: UUID().uuidString)) else { throw BackendContractError.ineligibleOriginal }
        let fresh = try await temporary.stateFor(source.media).receipt(for: usage)
        return try .init(operation: target.operation, handoff: fresh.photoHandoff(expected: source.rendition), retryOf: target.retryOf)
    }
}

nonisolated private func pbChangedSource(_ source: PhotoSaveSource, field: String) -> PhotoSaveSource {
    let old = source.rendition
    let original = OriginalContent(capture: .init(rawValue: field == "capture-alias" ? "e\u{301}" : old.original.capture.rawValue),
        generation: old.original.generation, content: old.original.content)
    let rendition = RenditionIdentity(original: original, inputLogIdentity: old.inputLogIdentity, transformAssetIdentity: old.transformAssetIdentity,
        transformAssetVersion: old.transformAssetVersion, outputConfigurationIdentity: old.outputConfigurationIdentity, conversionVersion: old.conversionVersion,
        rendition: field == "rendition" ? .init(rawValue: "other-rendition") : old.rendition,
        deliveryContent: old.deliveryContent, publicationGeneration: old.publicationGeneration)
    let registration = RegistrationIdentity(destination: source.registration.destination,
        id: field == "registration" ? .init(rawValue: "other-registration") : source.registration.id, generation: source.registration.generation)
    return .init(storeIdentity: field == "store" ? .init(rawValue: UUID()) : source.storeIdentity, registration: registration,
        rendition: rendition, media: field == "media" ? .init(rawValue: "other-media") : source.media,
        capturedAt: field == "date" ? source.capturedAt.addingTimeInterval(1) : source.capturedAt,
        directoryIdentity: field == "directory" ? .init(device: 0, inode: 0) : source.directoryIdentity,
        fileIdentity: field == "file" ? .init(device: 0, inode: 0) : source.fileIdentity,
        leaf: field == "mime" ? "36EC1010-E106-4FCF-B52F-946B2EE43844.mp4"
            : (field == "leaf" ? "36EC1010-E106-4FCF-B52F-946B2EE43844.mov" : source.leaf),
        contentType: field == "mime" ? "video/mp4" : source.contentType)
}

nonisolated private func pbDisk(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
    mode: ExplorationStoreOpenMode, fault: RecordingStoreFault? = nil) throws -> any MediaDiskStore {
    switch candidate {
    case .atomicFile: try AtomicFileRecordingStore(run: run, mode: mode, fault: fault)
    case .sqlite: try SQLiteRecordingStore(run: run, mode: mode, fault: fault)
    }
}
nonisolated private func pbMutation(_ store: any MediaOperationStorePort, command: MediaOperationID,
    _ change: PhotoSaveBatchChange) async throws -> BackendStoreMutation {
    let snapshot = try await mediaSnapshot(store)
    return .init(expectedRevision: snapshot.revision, change: .photoBatch(command: command, value: change), expectedStoreIdentity: snapshot.storeIdentity)
}
nonisolated private func pbPhotoMutation(_ store: any MediaOperationStorePort, command: MediaOperationID,
    _ change: PhotoRegistrationChange) async throws -> BackendStoreMutation {
    let snapshot = try await mediaSnapshot(store)
    return .init(expectedRevision: snapshot.revision, change: .photo(command: command, value: change), expectedStoreIdentity: snapshot.storeIdentity)
}
nonisolated private func pbCommit(_ store: any MediaOperationStorePort, _ mutation: BackendStoreMutation) async throws -> BackendCommitReceipt {
    let result = await store.commit(mutation)
    guard case .committed(let receipt) = result else { throw BackendContractError.notCommitted }
    #expect(await store.lookupCommit(mutation) == .committed(receipt))
    return receipt
}
nonisolated private func pbWrite(_ store: any MediaOperationStorePort, command: MediaOperationID,
    _ change: PhotoSaveBatchChange) async throws -> BackendCommitReceipt { try await pbCommit(store, pbMutation(store, command: command, change)) }
nonisolated private func pbPhoto(_ store: any MediaOperationStorePort, command: MediaOperationID,
    _ change: PhotoRegistrationChange) async throws -> BackendCommitReceipt { try await pbCommit(store, pbPhotoMutation(store, command: command, change)) }
