import Foundation
import Testing
@testable import FrameRelay

struct MediaOperationStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func fixedBatchEvidenceConfirmationAndCleanupUseOneWriter(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let store = try mediaDisk(candidate, run: run, mode: .createNew, schemas: ["s21-contract"])
            let registration = try await mediaRegister(store)
            // Contract-only saved records; no H264 file is relabelled as Log/saved.
            let a = try await mediaSavedBinding(store, name: "batch-a", digit: "a")
            let b = try await mediaSavedBinding(store, name: "batch-b", digit: "b")
            let registered = try #require(try await mediaSnapshot(store).registrations.last)
            let revision = try await mediaSnapshot(store).revision
            let batch = try TransferBatch(id: .init(rawValue: "batch"), originals: [mediaDescriptor(a), mediaDescriptor(b)],
                operations: [.init(rawValue: "upload-a"), .init(rawValue: "upload-b")], onWiFi: true,
                registration: registered, expectedRevision: revision)
            _ = try await mediaCommit(store, .batch(batch))
            let snapshot = try await mediaSnapshot(store)
            #expect(snapshot.batches.first?.fixedTargets == [a.original, b.original])
            #expect(snapshot.requests.allSatisfy { $0.startCommitted })
            let rendition = mediaRendition(a.original)
            _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
            let context = RemoteOperationContext(operation: .init(rawValue: "upload-a"), registration: registration,
                target: .original(a.original), session: .init(rawValue: "session-a"))
            let evidence = VerificationEvidence(id: .init(rawValue: "proof-a"), context: context, finalSaveCompleted: true,
                verification: .finalDestinationReadBack(a.original.content), committed: true,
                schemaVersion: "s21-contract", observedAt: Date(timeIntervalSince1970: 1))
            _ = try await mediaCommit(store, .verification(command: .init(rawValue: "adopt-proof"), expected: context, evidence: evidence))
            let confirmation = try mediaConfirmation(rendition, registration: registration)
            // Another clip's capture and lease commits may intervene without
            // changing this clip's current rendition or any previous receipt.
            _ = try await mediaSavedBinding(store, name: "intervening-clip", digit: "c")
            let prior = try await mediaSnapshot(store)
            let receipt = try await mediaCommit(store, .confirmation(confirmation))
            #expect(receipt.previousRevision == prior.revision)
            let stale = BackendStoreMutation(expectedRevision: prior.revision,
                change: .confirmation(try mediaConfirmation(rendition, registration: registration, operation: "stale-confirm")))
            #expect(await store.commit(stale) == .rejected(.revisionConflict))
            let current = try await mediaSnapshot(store)
            #expect(current.confirmations.last?.commit == receipt)
            #expect(current.outbox == [.confirmation(try #require(current.confirmations.last))])
            let cleanup = RemovalIntent(operation: .init(rawValue: "cleanup"), original: a.original, purpose: .cleanup)
            let selection = CleanupEvidenceSelection(registration: registration,
                verificationCommand: .init(rawValue: "adopt-proof"), confirmationOperation: confirmation.operation)
            try await mediaReconcile(store, original: a.original)
            let originalState = try await mediaOriginalSnapshot(store)
            #expect(await store.commitOriginal(.init(operation: .init(rawValue: "caller-eligible"),
                expectedRevision: originalState.revision, change: .reserveRemoval(cleanup,
                expectedInvalidation: .init(rawValue: 0), expectedAccess: .init(rawValue: 0)))) == .rejected(.ineligibleOriginal))
            _ = try await mediaOriginalCommit(store, .reserveCleanup(cleanup, selection,
                expectedInvalidation: .init(rawValue: 0), expectedAccess: .init(rawValue: 0)))
            let invalidation = mediaInvalidation(rendition, registration: registration)
            let reserved = try await mediaOriginalSnapshot(store)
            #expect(await store.commitOriginal(.init(operation: .init(rawValue: "invalidation-after-cleanup"),
                expectedRevision: reserved.revision, change: .reserveInvalidation(.init(invalidation)))) == .rejected(.deletionUnresolved))
            _ = try await mediaOriginalCommit(store, .resolveRemoval(cleanup, .notRemoved))
            // A changed runtime policy never invalidates the accepted historical
            // cleanup journal, but refuses a new cleanup under an unsupported schema.
            let reopened = try mediaDisk(candidate, run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).confirmations == current.confirmations)
            #expect(try await mediaOriginalSnapshot(reopened).originals.first?.resolvedRemoval == cleanup)
            try await mediaReconcile(reopened, original: a.original)
            let after = try await mediaOriginalSnapshot(reopened)
            let retry = RemovalIntent(operation: .init(rawValue: "unsupported-cleanup"), original: a.original, purpose: .cleanup)
            #expect(await reopened.commitOriginal(.init(operation: .init(rawValue: "unsupported-cleanup-command"),
                expectedRevision: after.revision, change: .reserveCleanup(retry, selection,
                expectedInvalidation: .init(rawValue: 0), expectedAccess: .init(rawValue: 0)))) == .rejected(.unsupportedVersion))
        }
    }

    @Test(arguments: StorageCandidate.allCases, [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func confirmationFaultAndExactLookupSurviveInstanceReplacement(candidate: StorageCandidate, fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let (mutation, registration) = try await prepareConfirmation(candidate, run: run)
            let result = try await commitWithFault(candidate, run: run, mutation: mutation, fault: fault)
            if fault == .afterDiskCommitBeforeReply { #expect(result == .unknown) }
            else { #expect(result == .unavailable(.inaccessible)) }
            let reopened = try mediaDisk(candidate, run: .openExisting(at: run.url), mode: .openExisting)
            let loaded = try await mediaSnapshot(reopened)
            if fault == .beforeDiskCommit {
                #expect(loaded.confirmations.isEmpty && loaded.outbox.isEmpty)
                #expect(await reopened.lookupCommit(mutation) == .unknown)
            } else {
                let record = try #require(loaded.confirmations.first)
                #expect(loaded.outbox == [.confirmation(record)])
                #expect(await reopened.lookupCommit(mutation) == .committed(record.commit))
                #expect(await reopened.commit(mutation) == .committed(record.commit))
                let changed = BackendStoreMutation(expectedRevision: mutation.expectedRevision + 1, change: mutation.change)
                #expect(await reopened.lookupCommit(changed) == .rejected(.identityMismatch))
                let delivery = BackendSyncDelivery(command: .init(rawValue: "sync-delivered"),
                    entry: .confirmation(record), registration: registration, response: .confirmation(record.intent.operation))
                _ = try await mediaCommit(reopened, .delivered(delivery))
                let again = try mediaDisk(candidate, run: run, mode: .openExisting)
                #expect(try await mediaSnapshot(again).outbox.isEmpty)
                #expect(try await mediaSnapshot(again).confirmations == [record])
            }
        }
    }

    @Test func invalidationRequiresExactReaderReleaseAndCurrentEpochAndRetainsTombstone() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await mediaRegister(store)
            let original = try mediaOriginal("remote")
            let rendition = mediaRendition(original)
            _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
            _ = try await mediaCommit(store, .confirmation(try mediaConfirmation(rendition, registration: registration)))
            let lease = MediaReadLease(id: .init(rawValue: "media-reader"), target: .rendition(rendition),
                operation: .init(rawValue: "play"), registration: registration, context: .playback(.init(rawValue: "play-session")),
                epoch: .init(rawValue: "sdk-instance"), accessGeneration: .init(rawValue: 1))
            _ = try await mediaOriginalCommit(store, .acquireMedia(lease))
            let invalidation = mediaInvalidation(rendition, registration: registration)
            _ = try await mediaOriginalCommit(store, .reserveInvalidation(.init(invalidation)))
            var snapshot = try await mediaSnapshot(store)
            #expect(await store.commit(.init(expectedRevision: snapshot.revision,
                change: .invalidation(invalidation, .init(record: invalidation)))) == .rejected(.readersActive))
            let wrongSession = MediaReadLease(id: lease.id, target: lease.target, operation: lease.operation,
                registration: registration, context: .playback(.init(rawValue: "late-old-session")),
                epoch: lease.epoch, accessGeneration: lease.accessGeneration)
            let before = try await mediaOriginalSnapshot(store)
            #expect(await store.commitOriginal(.init(operation: .init(rawValue: "wrong-release"),
                expectedRevision: before.revision, change: .releaseMedia(wrongSession))) == .rejected(.identityMismatch))
            _ = try await mediaOriginalCommit(store, .releaseMedia(lease))
            try await mediaReconcile(store, original: original)
            let oldEpoch = try #require(try await mediaOriginalSnapshot(store).reconciliationEpoch)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let access = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            #expect(await access.reconcileReaders(original) == .inProgress)
            #expect(await access.recoverPersistedMediaReaders(original) == .unknown)
            snapshot = try await mediaSnapshot(reopened)
            #expect(await reopened.commit(.init(expectedRevision: snapshot.revision,
                change: .invalidation(invalidation, .init(record: invalidation)))) == .rejected(.readersActive))
            #expect(try await mediaOriginalSnapshot(reopened).reconciliationEpoch != oldEpoch)
            try await mediaReconcile(reopened, original: original)
            let receipt = try await mediaCommit(reopened, .invalidation(invalidation, .init(record: invalidation)))
            let acknowledgement = InvalidationAcknowledgement(record: invalidation, commit: receipt)
            #expect(await access.finishInvalidation(acknowledgement) == .succeeded(invalidation.id))
            let fake = InvalidationAcknowledgement(record: invalidation,
                commit: .init(key: invalidation.key, previousRevision: receipt.previousRevision + 1,
                              committedRevision: receipt.committedRevision + 1))
            #expect(await access.finishInvalidation(fake) == .unknown)
            let after = try await mediaOriginalSnapshot(reopened)
            #expect(after.originals.isEmpty) // Remote-only; no synthetic local binding.
            #expect(after.logicalOriginals.first?.invalidation == nil)
            #expect(after.logicalOriginals.first?.invalidationGeneration == invalidation.generation)
            for purpose in [MediaPurpose.download, .playback] {
                let current = try await mediaSnapshot(reopened)
                let request = MediaRequest(operation: .init(rawValue: "old-request-\(purpose)"),
                    target: .rendition(rendition), purpose: purpose, registration: registration, expectedStartRevision: current.revision)
                #expect(await reopened.commit(.init(expectedRevision: current.revision,
                    change: .request(command: request.operation, value: request))) == .rejected(.identityMismatch))
            }
            let newLease = MediaReadLease(id: .init(rawValue: "old-version-new-lease"), target: lease.target,
                operation: lease.operation, registration: registration, context: lease.context,
                epoch: lease.epoch, accessGeneration: .init(rawValue: 2))
            #expect(await reopened.commitOriginal(.init(operation: .init(rawValue: "old-lease-command"),
                expectedRevision: after.revision, change: .acquireMedia(newLease))) == .rejected(.identityMismatch))
            let delivery = BackendSyncDelivery(command: .init(rawValue: "ack-delivered"), entry: .invalidation(acknowledgement),
                registration: registration, response: .invalidation(invalidation.id))
            _ = try await mediaCommit(reopened, .delivered(delivery))
            let again = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let preserved = try await mediaSnapshot(again)
            #expect(preserved.invalidations == [acknowledgement])
            #expect(preserved.confirmationStates.first?.validConfirmation == nil)
            #expect(preserved.confirmationStates.first?.invalidatedRenditions == [rendition.rendition])
            #expect(!preserved.outbox.contains(.invalidation(acknowledgement)))
            #expect(await again.lookupInvalidation(acknowledgement) == .succeeded(invalidation.id))
        }
    }

    @Test func remoteIdentityMergesWithActualUnknownMovieAndKeepsReaders() async throws {
        try await withStorageRun { run in
            let originalBinding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let registration = try await mediaRegister(store)
            let original = OriginalContent(capture: originalBinding.original.capture, generation: .init(rawValue: 7),
                                           content: originalBinding.original.content)
            let rendition = mediaRendition(original)
            _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
            let lease = MediaReadLease(id: .init(rawValue: "remote-reader"), target: .rendition(rendition),
                operation: .init(rawValue: "remote-play"), registration: registration,
                context: .playback(.init(rawValue: "session")), epoch: .init(rawValue: "sdk"),
                accessGeneration: .init(rawValue: 1))
            _ = try await mediaOriginalCommit(store, .acquireMedia(lease))
            let access = ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run))
            guard case .succeeded(let bound) = await access.bind(originalBinding.reference,
                operation: .init(rawValue: "attach-local")) else { Issue.record("Bind failed"); return }
            #expect(bound.original == original)
            #expect(bound.saveRecord.result == originalBinding.saveRecord.result)
            #expect(bound.saveRecord.result != .saved)
            var logical = try #require(try await mediaOriginalSnapshot(store).logicalOriginals.first)
            #expect(logical.mediaReaders == [lease])
            guard case .succeeded(let playback) = await access.acquirePlayback(original,
                operation: .init(rawValue: "actual-fd"), leaseID: .init(rawValue: "actual-reader")) else {
                Issue.record("Actual file open failed"); return
            }
            let invalidation = mediaInvalidation(rendition, registration: registration)
            #expect(await access.reserveInvalidation(invalidation) == .succeeded(.init(record: invalidation)))
            #expect(await access.reconcileReaders(original) == .inProgress)
            _ = await access.releaseRead(playback.lease)
            logical = try #require(try await mediaOriginalSnapshot(store).logicalOriginals.first)
            #expect(logical.readers.isEmpty && logical.mediaReaders == [lease])
            #expect(logical.accessGeneration.rawValue == 2)
            let before = try await mediaSnapshot(store)
            #expect(await store.commit(.init(expectedRevision: before.revision,
                change: .invalidation(invalidation, .init(record: invalidation)))) == .rejected(.readersActive))
            let again = try SQLiteRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaOriginalSnapshot(again).logicalOriginals.first?.original == original)
            #expect(try await mediaOriginalSnapshot(again).originals.first?.binding.original.generation.rawValue == 7)
        }
    }

    @Test func nonRecipientCanAdoptNewPublicationButWrongReservationsLeaveNoState() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await mediaRegister(store)
            let original = try mediaOriginal("manifest-only")
            let first = mediaRendition(original)
            let second = mediaRendition(original, version: 2)
            _ = try await mediaCommit(store, .publication(mediaPublication(first, registration: registration)))
            _ = try await mediaCommit(store, .publication(mediaPublication(second, registration: registration, observation: 2, generation: 5)))
            #expect(try await mediaSnapshot(store).confirmationStates.first?.generation.rawValue == 5)
            let state = try await mediaOriginalSnapshot(store)
            let records = [
                mediaInvalidation(first, registration: registration, generation: 6),
                mediaInvalidation(second, registration: registration, generation: 5),
                mediaInvalidation(second, registration: .init(destination: registration.destination,
                    id: .init(rawValue: "different-registration"), generation: .init(rawValue: 99)), generation: 6)
            ]
            for (index, record) in records.enumerated() {
                let result = await store.commitOriginal(.init(operation: .init(rawValue: "invalid-reservation-\(index)"),
                    expectedRevision: state.revision, change: .reserveInvalidation(.init(record))))
                if case .rejected = result {} else { Issue.record("Invalid reservation accepted") }
                #expect(try await mediaOriginalSnapshot(store).logicalOriginals.first?.invalidation == nil)
            }
            let record = mediaInvalidation(second, registration: registration, generation: 6)
            _ = try await mediaOriginalCommit(store, .reserveInvalidation(.init(record)))
            #expect(try await mediaOriginalSnapshot(store).logicalOriginals.first?.invalidation?.record == record)
        }
    }

    @Test func rejectedOldRetrievalDoesNotBecomeARecipientOrBlockNewPublicationForever() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await mediaRegister(store)
            let original = try mediaOriginal("rejected-get")
            let first = mediaRendition(original)
            let second = mediaRendition(original, version: 2)
            _ = try await mediaCommit(store, .publication(mediaPublication(first, registration: registration)))
            let lease = MediaReadLease(id: .init(rawValue: "get-reader"), target: .rendition(first),
                operation: .init(rawValue: "get-operation"), registration: registration,
                context: .transport(.init(rawValue: "get-attempt")), epoch: .init(rawValue: "transport-owner"),
                accessGeneration: .init(rawValue: 1))
            _ = try await mediaOriginalCommit(store, .acquireMedia(lease))
            _ = try await mediaOriginalCommit(store, .releaseMedia(lease))
            let publication = mediaPublication(second, registration: registration, observation: 2, generation: 5)
            let before = try await mediaSnapshot(store)
            #expect(await store.commit(.init(expectedRevision: before.revision, change: .publication(publication)))
                == .rejected(.awaitingAcknowledgements))
            // Explicit control-plane fixture: V2 won before the old GET was
            // accepted; the old GET returned no bytes/distribution receipt.
            let result = MediaDistributionObservation(command: .init(rawValue: "get-reconciled"), lease: lease,
                observation: .init(rawValue: 1), result: .notExecuted)
            _ = try await mediaCommit(store, .distribution(result))
            _ = try await mediaCommit(store, .publication(publication))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.confirmationStates.first?.current == second)
            #expect(snapshot.confirmationStates.first?.generation.rawValue == 5)
            #expect(snapshot.confirmations.isEmpty && snapshot.invalidations.isEmpty && snapshot.outbox.isEmpty)
            #expect(snapshot.distributionObservations.first?.observation == result)
        }
    }
    @Test(arguments: StorageCandidate.allCases, [false, true])
    func invalidationFaultKeepsReservationOrCommitsTombstoneAndAckTogether(candidate: StorageCandidate,
                                                                        afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let registration = RegistrationIdentity(destination: .init(rawValue: "s21-destination"),
                id: .init(rawValue: "s21-registration"), generation: .init(rawValue: 1))
            let rendition = mediaRendition(try mediaOriginal("invalidation-fault"))
            let record = mediaInvalidation(rendition, registration: registration)
            let identity = record.key.operationIdentity
            // Only this exact backend mutation fails; the same writer's actual
            // quiescence observation is durably committed before the fault.
            let store = try mediaDisk(candidate, run: run, mode: .createNew,
                fault: afterCommit ? .afterBackendCommitBeforeReply(identity) : .beforeBackendCommit(identity))
            _ = try await mediaRegister(store, registration: registration)
            _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
            _ = try await mediaCommit(store, .confirmation(try mediaConfirmation(rendition, registration: registration)))
            _ = try await mediaOriginalCommit(store, .reserveInvalidation(.init(record)))
            try await mediaReconcile(store, original: rendition.original)
            let before = try await mediaSnapshot(store)
            let mutation = BackendStoreMutation(expectedRevision: before.revision,
                change: .invalidation(record, .init(record: record)))
            #expect(await store.commit(mutation) == (afterCommit ? .unknown : .unavailable(.inaccessible)))
            let reopened = try mediaDisk(candidate, run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            let original = try #require(try await mediaOriginalSnapshot(reopened).logicalOriginals.first)
            if afterCommit {
                let ack = try #require(snapshot.invalidations.first)
                #expect(snapshot.revision == before.revision + 1)
                #expect(snapshot.outbox.contains(.invalidation(ack)))
                #expect(snapshot.confirmationStates.first?.validConfirmation == nil)
                #expect(original.invalidation == nil && original.invalidationGeneration == record.generation)
                #expect(await reopened.lookupCommit(mutation) == .committed(ack.commit))
                #expect(await reopened.commit(mutation) == .committed(ack.commit))
                #expect(await reopened.lookupInvalidation(ack) == .succeeded(record.id))
            } else {
                #expect(snapshot == before)
                #expect(original.invalidation?.record == record)
                #expect(snapshot.invalidations.isEmpty)
                #expect(snapshot.confirmationStates.first?.validConfirmation != nil)
                #expect(await reopened.lookupCommit(mutation) == .unknown)
            }
        }
    }

    @Test func acceptedDistributionRequiresAckEvenWithoutAConfirmation() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await mediaRegister(store)
            let first = mediaRendition(try mediaOriginal("received-unconfirmed"))
            let second = mediaRendition(first.original, version: 2)
            _ = try await mediaCommit(store, .publication(mediaPublication(first, registration: registration)))
            let lease = MediaReadLease(id: .init(rawValue: "accepted-reader"), target: .rendition(first),
                operation: .init(rawValue: "accepted-get"), registration: registration,
                context: .transport(.init(rawValue: "accepted-attempt")), epoch: .init(rawValue: "sdk"),
                accessGeneration: .init(rawValue: 1))
            _ = try await mediaOriginalCommit(store, .acquireMedia(lease))
            _ = try await mediaOriginalCommit(store, .releaseMedia(lease))
            let distribution = try mediaConfirmation(first, registration: registration).playback.distribution
            _ = try await mediaCommit(store, .distribution(.init(command: .init(rawValue: "accepted-proof"), lease: lease,
                observation: .init(rawValue: 1), result: .succeeded(distribution))))
            var snapshot = try await mediaSnapshot(store)
            #expect(snapshot.confirmations.isEmpty)
            let next = mediaPublication(second, registration: registration, observation: 2, generation: 1)
            #expect(await store.commit(.init(expectedRevision: snapshot.revision, change: .publication(next)))
                == .rejected(.awaitingAcknowledgements))
            // Later cancellation/zero bytes must not erase an accepted receipt.
            #expect(await store.commit(.init(expectedRevision: snapshot.revision,
                change: .distribution(.init(command: .init(rawValue: "erase-distribution"), lease: lease,
                    observation: .init(rawValue: 2), result: .notExecuted)))) == .rejected(.identityMismatch))
            let record = mediaInvalidation(first, registration: registration)
            _ = try await mediaOriginalCommit(store, .reserveInvalidation(.init(record)))
            snapshot = try await mediaSnapshot(store)
            #expect(await store.commit(.init(expectedRevision: snapshot.revision, change: .publication(next)))
                == .rejected(.deletionUnresolved))
            try await mediaReconcile(store, original: first.original)
            _ = try await mediaCommit(store, .invalidation(record, .init(record: record)))
            _ = try await mediaCommit(store, .publication(next))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let preserved = try await mediaSnapshot(reopened)
            #expect(preserved.confirmations.isEmpty)
            #expect(preserved.confirmationStates.first?.current == second)
            #expect(preserved.confirmationStates.first?.invalidatedRenditions == [first.rendition])
            #expect(preserved.invalidations.count == 1 && preserved.distributionObservations.count == 1)
        }
    }

    @Test func unsupportedAndAssemblyEvidenceRemainFactsWithoutCleanupAuthority() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew, supportedVerificationSchemas: ["supported"])
            let registration = try await mediaRegister(store)
            let binding = try await mediaSavedBinding(store, name: "proof-policy", digit: "d")
            let rendition = mediaRendition(binding.original)
            _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
            let confirmation = try mediaConfirmation(rendition, registration: registration)
            _ = try await mediaCommit(store, .confirmation(confirmation))
            try await mediaReconcile(store, original: binding.original)
            let context = RemoteOperationContext(operation: .init(rawValue: "upload"), registration: registration,
                target: .original(binding.original), session: .init(rawValue: "upload-session"))
            for (index, schema) in ["unknown-schema", "supported"].enumerated() {
                let evidence = VerificationEvidence(id: .init(rawValue: "proof-\(index)"), context: context,
                    finalSaveCompleted: true,
                    verification: index == 0 ? .finalDestinationReadBack(binding.original.content) : .assemblyOnly(binding.original.content),
                    committed: true, schemaVersion: schema, observedAt: Date(timeIntervalSince1970: 1))
                let command = MediaOperationID(rawValue: "proof-command-\(index)")
                _ = try await mediaCommit(store, .verification(command: command, expected: context, evidence: evidence))
                let snapshot = try await mediaOriginalSnapshot(store)
                let intent = RemovalIntent(operation: .init(rawValue: "cleanup-\(index)"), original: binding.original, purpose: .cleanup)
                let selection = CleanupEvidenceSelection(registration: registration, verificationCommand: command,
                    confirmationOperation: confirmation.operation)
                #expect(await store.commitOriginal(.init(operation: .init(rawValue: "cleanup-command-\(index)"),
                    expectedRevision: snapshot.revision, change: .reserveCleanup(intent, selection,
                        expectedInvalidation: .init(rawValue: 0), expectedAccess: .init(rawValue: 0))))
                    == .rejected(index == 0 ? .unsupportedVersion : .ineligibleOriginal))
            }
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).verifications.count == 2)
            #expect(try await mediaOriginalSnapshot(reopened).originals.first?.removal == nil)
        }
    }

    @Test(arguments: ["prepared-playback", "broken-revision", "invalid-content"])
    func decodedNestedValuesAndMergedJournalReceiptsAreRevalidated(corruption: String) async throws {
        try await withStorageRun { run in
            let store = try AtomicFileRecordingStore(run: run, mode: .createNew)
            let registration = try await mediaRegister(store)
            let binding = try await mediaSavedBinding(store, name: "decode-validation", digit: "e")
            let rendition = mediaRendition(binding.original)
            _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
            _ = try await mediaCommit(store, .confirmation(try mediaConfirmation(rendition, registration: registration)))
            let file = run.url.appendingPathComponent("recordings.json")
            let valid = try Data(contentsOf: file)
            let damaged: Data
            if corruption == "broken-revision" {
                var document = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
                var journal = try #require(document["backendJournal"] as? [[String: Any]])
                var receipt = try #require(journal[0]["receipt"] as? [String: Any])
                receipt["committedRevision"] = 2
                journal[0]["receipt"] = receipt
                document["backendJournal"] = journal
                damaged = try JSONSerialization.data(withJSONObject: document)
            } else {
                let source = try #require(String(data: valid, encoding: .utf8))
                let modified = corruption == "prepared-playback"
                    ? source.replacingOccurrences(of: "\"played\":{}", with: "\"prepared\":{}")
                    : source.replacingOccurrences(of: binding.original.content.digest, with: "invalid-digest")
                #expect(source != modified)
                damaged = Data(modified.utf8)
            }
            try damaged.write(to: file, options: .atomic)
            #expect(throws: ExplorationStorageError.corruptStore) {
                try AtomicFileRecordingStore(run: run, mode: .openExisting)
            }
            #expect(await store.load() == .unavailable(.corruptStore))
            #expect(try Data(contentsOf: file) == damaged)
        }
    }
}

typealias MediaDiskStore = RecordingStorePort & OriginalStorePort & MediaOperationStorePort

nonisolated private func mediaDisk(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
    mode: ExplorationStoreOpenMode, fault: RecordingStoreFault? = nil, schemas: Set<String> = []) throws -> any MediaDiskStore {
    switch candidate {
    case .atomicFile: try AtomicFileRecordingStore(run: run, mode: mode, fault: fault, supportedVerificationSchemas: schemas)
    case .sqlite: try SQLiteRecordingStore(run: run, mode: mode, fault: fault, supportedVerificationSchemas: schemas)
    }
}

nonisolated func mediaSnapshot(_ store: any MediaOperationStorePort) async throws -> BackendStoreSnapshot {
    guard case .loaded(let value) = await store.load() else { throw BackendContractError.unavailable }
    return value
}
nonisolated func mediaOriginalSnapshot(_ store: any OriginalStorePort) async throws -> OriginalStoreSnapshot {
    guard case .succeeded(let value) = await store.loadOriginalState() else { throw BackendContractError.unavailable }
    return value
}
nonisolated func mediaCommit(_ store: any MediaOperationStorePort, _ change: BackendStoreChange) async throws -> BackendCommitReceipt {
    let snapshot = try await mediaSnapshot(store)
    guard case .committed(let value) = await store.commit(.init(expectedRevision: snapshot.revision, change: change)) else {
        throw BackendContractError.notCommitted
    }
    return value
}
nonisolated func mediaOriginalCommit(_ store: any OriginalStorePort, _ change: OriginalStoreChange) async throws -> OriginalStoreCommitReceipt {
    let snapshot = try await mediaOriginalSnapshot(store)
    guard case .committed(let value) = await store.commitOriginal(.init(operation: .init(rawValue: UUID().uuidString),
        expectedRevision: snapshot.revision, change: change)) else { throw BackendContractError.notCommitted }
    return value
}
nonisolated func mediaRegister(_ store: any MediaOperationStorePort,
    registration: RegistrationIdentity = .init(destination: .init(rawValue: "s21-destination"),
        id: .init(rawValue: "s21-registration"), generation: .init(rawValue: 1))) async throws -> RegistrationIdentity {
    let intent = RegistrationIntent(operation: .init(rawValue: "register-\(registration.id.rawValue)"), destination: registration.destination)
    _ = try await mediaCommit(store, .registrationIntent(intent))
    _ = try await mediaCommit(store, .registration(.init(intent: intent, registration: registration)))
    return registration
}
nonisolated private func mediaOriginal(_ name: String) throws -> OriginalContent {
    .init(capture: .init(rawValue: name), generation: .init(rawValue: 1),
          content: try .init(byteCount: 4096, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
}
nonisolated private func mediaRendition(_ original: OriginalContent, version: UInt64 = 1) -> RenditionIdentity {
    .init(original: original, inputLogIdentity: "contract-log", transformAssetIdentity: "contract-transform",
        transformAssetVersion: "contract-v1", outputConfigurationIdentity: "contract-output",
        conversionVersion: "contract-conversion", rendition: .init(rawValue: "rendition-\(version)"),
        deliveryContent: original.content, publicationGeneration: .init(rawValue: version))
}
nonisolated func mediaPublication(_ rendition: RenditionIdentity, registration: RegistrationIdentity,
    observation: UInt64 = 1, generation: UInt64 = 0) -> PublishedRenditionObservation {
    .init(command: .init(rawValue: "publication-\(rendition.original.capture.rawValue)-\(observation)"),
          registration: registration, rendition: rendition, observation: .init(rawValue: observation),
          invalidationGeneration: .init(rawValue: generation))
}
nonisolated private func mediaInvalidation(_ rendition: RenditionIdentity, registration: RegistrationIdentity,
    generation: UInt64 = 1) -> InvalidationRecord {
    .init(id: .init(rawValue: "invalidation-\(generation)"), rendition: rendition,
          registration: registration, generation: .init(rawValue: generation))
}
nonisolated private func mediaConfirmation(_ rendition: RenditionIdentity, registration: RegistrationIdentity,
    operation: String = "confirm", generation: UInt64 = 0) throws -> ConfirmationIntent {
    // Synthetic played/distribution contract input only. No real rendition player
    // or server is claimed by these storage-atomicity tests.
    let distributionOperation = MediaOperationID(rawValue: "distribution-\(operation)")
    let distribution = DistributionReceipt(operation: distributionOperation, rendition: rendition, registration: registration,
        commit: .init(key: .distribution(distributionOperation, rendition, registration), previousRevision: 20, committedRevision: 21))
    return .init(operation: .init(rawValue: operation),
        playback: try .init(distribution: distribution, session: .init(rawValue: "session-\(operation)"),
                            invalidationGeneration: .init(rawValue: generation), observation: .played))
}
nonisolated func mediaReconcile(_ store: any OriginalStorePort, original: OriginalContent) async throws {
    let snapshot = try await mediaOriginalSnapshot(store)
    let state = try #require(snapshot.logicalOriginals.first { $0.original == original })
    let epoch = try #require(snapshot.reconciliationEpoch)
    // Explicit synthetic SDK/OS observations; product enumeration is S23/S25.
    let observations = Dictionary(uniqueKeysWithValues: MediaReaderOwner.allCases.map {
        ($0, EvidenceID(rawValue: "contract-observation-\($0.rawValue)"))
    })
    _ = try await mediaOriginalCommit(store, .reconcileMedia(.init(original: original,
        accessGeneration: state.accessGeneration, epoch: epoch, observations: observations)))
}
nonisolated private func mediaSavedBinding(_ store: any MediaDiskStore, name: String, digit: String) async throws -> OriginalBinding {
    let fixture = try CaptureFixture(clip: name)
    let result = try syntheticResult(fixture)
    guard case .committed = await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent)),
          case .committed(let receipt) = await store.execute(.commitResult(fixture.token(4), expectedRevision: 1, result)) else {
        throw BackendContractError.notCommitted
    }
    let binding = OriginalBinding(original: .init(capture: fixture.context.capture, generation: .init(rawValue: 1),
        content: try .init(byteCount: fixture.file.byteCount, algorithm: "sha256", digest: String(repeating: digit, count: 64))),
        reference: fixture.intent.original, saveRecord: result, saveCommit: receipt)
    _ = try await mediaOriginalCommit(store, .bind(binding))
    return binding
}
nonisolated private func mediaDescriptor(_ binding: OriginalBinding) -> OriginalDescriptor {
    .init(original: binding.original, reference: binding.reference, saveResult: binding.saveRecord.result,
        saveCommit: binding.saveCommit, savedReference: binding.reference, savedContext: binding.saveRecord.intent.context,
        presence: .present, readiness: .ready)
}
nonisolated private func prepareConfirmation(_ candidate: StorageCandidate, run: ExplorationRunDirectory) async throws
    -> (BackendStoreMutation, RegistrationIdentity) {
    let store = try mediaDisk(candidate, run: run, mode: .createNew)
    let registration = try await mediaRegister(store)
    let rendition = mediaRendition(try mediaOriginal("fault"))
    _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
    return (.init(expectedRevision: try await mediaSnapshot(store).revision,
        change: .confirmation(try mediaConfirmation(rendition, registration: registration))), registration)
}
nonisolated private func commitWithFault(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
    mutation: BackendStoreMutation, fault: RecordingStoreFault) async throws -> BackendCommitResult {
    let store = try mediaDisk(candidate, run: run, mode: .openExisting, fault: fault)
    return await store.commit(mutation)
}
