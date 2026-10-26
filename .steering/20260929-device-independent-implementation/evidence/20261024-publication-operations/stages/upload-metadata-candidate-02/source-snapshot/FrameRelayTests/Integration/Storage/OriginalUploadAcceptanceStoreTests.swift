import Foundation
import Testing
@testable import FrameRelay

/// Every case owns a new UUID root and newly generated H264/PCM files. Saved
/// classifications, stat faults and remote values are explicit technical inputs,
/// never a camera, native network, formal transform or media sender proof.
struct OriginalUploadAcceptanceStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func mixedFixedMembershipAtomicallyQueuesOnlySavedPresentChildren(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate)
            let saved = try await f.source("saved"), partial = try await f.source("partial", kind: .partial)
            let unknown = try await f.source("unknown", kind: .unknown), missing = try await f.source("missing")
            let plan = try f.plan([saved, partial, unknown, missing],
                presences: [await f.presence(saved), await f.presence(partial), await f.presence(unknown), .missing])
            let before = try await mediaSnapshot(f.store)
            let record = try await f.commit(plan)
            #expect(record.children.map(\.decision) == [.accepted, .notProcessed(.saveNotCompleted),
                .notProcessed(.saveNotCompleted), .notProcessed(.fileMissing)])
            #expect(record.isCommitted && record.children.count == 4 && record.plan == plan)
            let after = try await mediaSnapshot(f.store)
            #expect(after.batches == before.batches && after.requests.count == before.requests.count + 1)
            let request = try #require(after.requests.last)
            #expect(request == record.children[0].initialRequest)
            #expect(request.expectedStartRevision == record.commit.previousRevision && request.expectedStartRevision > saved.saveCommit.committedRevision)
            #expect(request.startCommitted && !request.canRun && request.transport == .queued && request.intent == .running)
            #expect(request.attempt == nil && request.session == nil && !request.hasReconciled && request.remote == .unknown)
            #expect(after.backgroundTasks.isEmpty && after.distributionObservations.isEmpty && after.outbox.isEmpty)
            let state = try await mediaOriginalSnapshot(f.store)
            #expect(state.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
            for source in [saved, partial, unknown, missing] { try await f.assertBytes(source) }
            let reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == after)
            #expect(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
            if candidate == .atomicFile {
                let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: run.url.appendingPathComponent(candidate.fileName))) as? [String: Any])
                #expect(object["schema"] as? Int == 7 && object["originalUploadAcceptances"] == nil)
            }
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["missing", "inaccessible", "unknown", "zero", "wrong-size"])
    func zeroEligibleStillCommitsEveryFrozenStatAndReservesItsChild(candidate: StorageCandidate, observation: String) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate), binding = try await f.source("stat")
            let presence: OriginalUploadFilePresence
            let reason: OriginalUploadAcceptanceNonProcessing
            switch observation {
            case "missing": presence = .missing; reason = .fileMissing
            case "inaccessible": presence = .inaccessible; reason = .fileInaccessible
            case "unknown": presence = .unknown; reason = .fileUnknown
            case "zero": presence = .present(byteCount: 0); reason = .byteCountMismatch
            default: presence = .present(byteCount: binding.original.content.byteCount + 1); reason = .byteCountMismatch
            }
            let plan = try f.plan([binding], presences: [presence])
            let record = try await f.commit(plan)
            #expect(record.children[0].decision == .notProcessed(reason) && record.children[0].initialRequest == nil)
            let after = try await mediaSnapshot(f.store)
            #expect(after.requests.isEmpty && after.batches.isEmpty && after.originalUploadAcceptances == [record])
            let reused = try f.plan([binding], presences: [.missing], parent: UUID().uuidString,
                operations: [plan.request.targets[0].operation])
            #expect(await f.store.commit(try await f.mutation(reused)) == .rejected(.identityMismatch))
            let reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == after)
            #expect(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
            // These are frozen observation faults; the source bytes are retained.
            try await f.assertBytes(binding)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func changedBindingsStayPerChildWhileUUIDAndCurrentRegistrationRejectTheParent(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate), binding = try await f.source("binding")
            for field in ["reference", "save-commit", "record-context", "content"] {
                let changed = try uploadChangedBinding(binding, field: field)
                let plan = try f.plan([changed], presences: [.present(byteCount: changed.original.content.byteCount)])
                let record = try await f.commit(plan)
                #expect(record.children[0].decision == .notProcessed(field == "content" ? .bindingUnavailable : .bindingChanged))
                #expect(try await mediaSnapshot(f.store).requests.isEmpty)
            }
            let valid = try f.plan([binding], presences: [await f.presence(binding)])
            let mutation = try await f.mutation(valid)
            #expect(await f.store.commit(.init(expectedRevision: mutation.expectedRevision, change: mutation.change)) == .rejected(.identityMismatch))
            #expect(await f.store.commit(.init(expectedRevision: mutation.expectedRevision, change: mutation.change,
                expectedStoreIdentity: .init(rawValue: UUID()))) == .rejected(.identityMismatch))
            let wrongUUID = try f.plan([binding], presences: [await f.presence(binding)], identity: .init(rawValue: UUID()))
            #expect(await f.store.commit(try await f.mutation(wrongUUID)) == .rejected(.identityMismatch))
            let newer = RegistrationIdentity(destination: f.registration.server.registration.destination,
                id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2))
            _ = try await mediaRegister(f.store, registration: newer)
            #expect(await f.store.commit(try await f.mutation(valid)) == .rejected(.identityMismatch))
            let current = try #require(try await mediaSnapshot(f.store).registrations.last)
            let refreshed = try f.plan([binding], presences: [await f.presence(binding)], registration: current)
            let record = try await f.commit(refreshed)
            #expect(record.children[0].decision == .accepted)
            let reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened).originalUploadAcceptances.last == record)
            try await f.assertBytes(binding)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func liveRecordingTokenIsCheckedWithoutReinterpretingTheHistoricalProjection(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate), binding = try await f.source("live-recording")
            let plan = try f.plan([binding], presences: [await f.presence(binding)])
            let before = try await mediaSnapshot(f.store)
            let originals = try await mediaOriginalSnapshot(f.store)
            guard case .loaded(let recordings) = await f.store.loadRecordings() else { throw BackendContractError.unavailable }
            var projection = MediaStoreProjection()
            projection.originals = originals.logicalOriginals
            projection.registrations = before.registrations; projection.registrationIntents = before.registrationIntents
            var document = RecordingStoreDocument()
            document.entries = recordings.recordings.map {
                .init(intentToken: $0.intentToken, intent: $0.intent, revision: $0.revision, resultToken: $0.resultToken, result: $0.result)
            }
            try document.requireOriginalUploadCurrentRecordings(plan, projection: projection)
            let token = binding.saveCommit.token
            document.entries[0].resultToken = .init(context: token.context, operation: token.operation, ordinal: token.ordinal + 1)
            #expect(throws: BackendContractError.identityMismatch) {
                try document.requireOriginalUploadCurrentRecordings(plan, projection: projection)
            }
            // This isolated memory copy is not written to the disk. Replay has
            // its own event-ordered binding, rather than today's entry projection.
            let receipt = BackendCommitReceipt(key: .originalUploadAcceptance(plan.request.parent), previousRevision: before.revision,
                committedRevision: before.revision + 1)
            try projection.applyOriginalUploadAcceptance(plan, receipt: receipt, expectedStoreIdentity: f.identity)
            #expect(projection.originalUploadAcceptances[0].children[0].decision == .accepted)
            #expect(try await mediaSnapshot(f.store) == before)
            try await f.assertBytes(binding)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func initialReceiptAndLookupRemainExactAfterPauseMetadataLaterCapturesAndReregistration(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate), binding = try await f.source("initial")
            let record = try await f.commit(f.plan([binding], presences: [await f.presence(binding)]))
            let initial = try #require(record.children[0].initialRequest)
            let pause = try MediaPersonControlPlan(parent: .init(rawValue: UUID().uuidString), storeIdentity: f.identity,
                scope: .single, action: .pause, children: [.init(command: .init(rawValue: UUID().uuidString), target: .init(initial))])
            _ = try await f.backend(.personControl(pause))
            _ = try await mediaCommit(f.store, .requestTransition(command: .init(rawValue: UUID().uuidString), operation: initial.operation,
                target: initial.target, registration: initial.registration, value: .reconciled(.init(context: .init(operation: initial.operation,
                    registration: initial.registration, target: initial.target, session: .init(rawValue: "fixture-metadata-session")),
                    observation: .init(rawValue: 1), result: .notExecuted))))
            let duplicate = try await f.commit(f.plan([binding], presences: [await f.presence(binding)]))
            #expect(duplicate.children[0].decision == .notProcessed(.alreadyRequested))
            let later = try await f.source("later")
            let newer = RegistrationIdentity(destination: f.registration.server.registration.destination,
                id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2))
            _ = try await mediaRegister(f.store, registration: newer)
            let after = try await mediaSnapshot(f.store)
            #expect(after.requests.count == 1 && after.requests[0].intent == .paused && after.requests[0].hasReconciled)
            #expect(after.originalUploadAcceptances[0] == record && record.children[0].initialRequest?.hasReconciled == false)
            #expect(record.children[0].initialRequest?.intent == .running && record.isCommitted)
            #expect(await f.store.lookupCommit(record.mutation) == .committed(record.commit))
            #expect(await f.store.commit(record.mutation) == .committed(record.commit))
            let changedEnvelope = BackendStoreMutation(expectedRevision: after.revision, change: record.mutation.change,
                expectedStoreIdentity: f.identity)
            #expect(await f.store.lookupCommit(changedEnvelope) == .rejected(.identityMismatch))
            let changedStat = try OriginalUploadAcceptancePlan(request: record.plan.request, presences: [.missing])
            #expect(await f.store.lookupCommit(.init(expectedRevision: record.commit.previousRevision,
                change: .originalUploadAcceptance(changedStat), expectedStoreIdentity: f.identity)) == .rejected(.identityMismatch))
            let reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == after)
            #expect(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
            try await f.assertBytes(binding); try await f.assertBytes(later)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func exactLostEnvelopeReopensWithoutRestatRebaseOrCreatingAnotherChild(candidate: StorageCandidate, afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let parent = MediaOperationID(rawValue: "lost-parent-\u{00e9}")
            let fault: RecordingStoreFault = afterCommit ? .afterBackendCommitBeforeReply(.originalUploadAcceptance(parent))
                : .beforeBackendCommit(.originalUploadAcceptance(parent))
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate, fault: fault), binding = try await f.source("fault")
            let plan = try f.plan([binding], presences: [await f.presence(binding)], parent: parent.rawValue)
            let mutation = try await f.mutation(plan)
            #expect(await f.store.commit(mutation) == (afterCommit ? .unknown : .unavailable(.inaccessible)))
            let reopened = try f.reopen()
            let before = try await mediaSnapshot(reopened)
            #expect(before.originalUploadAcceptances.count == (afterCommit ? 1 : 0) && before.requests.count == (afterCommit ? 1 : 0))
            if afterCommit {
                let record = try #require(before.originalUploadAcceptances.first)
                #expect(OriginalUploadAcceptanceValueValidation.exact(record.mutation, mutation))
                #expect(await reopened.lookupCommit(mutation) == .committed(record.commit))
                let aliasRequest = try OriginalUploadAcceptanceRequest(parent: .init(rawValue: "lost-parent-e\u{0301}"),
                    storeIdentity: f.identity, registration: plan.request.registration, scope: .single, targets: plan.request.targets)
                let alias = try OriginalUploadAcceptancePlan(request: aliasRequest, presences: plan.presences)
                #expect(await reopened.lookupCommit(.init(expectedRevision: mutation.expectedRevision,
                    change: .originalUploadAcceptance(alias), expectedStoreIdentity: f.identity)) == .rejected(.identityMismatch))
                #expect(await reopened.commit(mutation) == .committed(record.commit))
            } else {
                #expect(await reopened.lookupCommit(mutation) == .unknown)
                // A definite later change cannot make a missing original
                // envelope commit; the consumer must keep its unknown binding.
                _ = try await mediaCommit(reopened, .publication(mediaPublication(statusRendition(binding.original),
                    registration: f.registration.server.registration)))
                #expect(await reopened.lookupCommit(mutation) == .unknown)
                #expect(await reopened.commit(mutation) == .rejected(.revisionConflict))
                #expect(try await mediaSnapshot(reopened).originalUploadAcceptances.isEmpty)
            }
            #expect(try await mediaSnapshot(reopened).backgroundTasks.isEmpty)
            try await f.assertBytes(binding)
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["removal", "invalidation"])
    func reservationsKeepTheFixedChildUnprocessedAndJournalInTheExactRemovalInventory(candidate: StorageCandidate, boundary: String) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate)
            let held = try await f.source("held"), peer = try await f.source("peer")
            let plan = try f.plan([held, peer], presences: [await f.presence(held), await f.presence(peer)])
            if boundary == "removal" { try await f.reserveRemoval(held) }
            else { try await f.reserveInvalidation(held) }
            let record = try await f.commit(plan)
            #expect(record.children.map(\.decision) == [.notProcessed(boundary == "removal" ? .removalReserved : .invalidated), .accepted])
            guard case .succeeded(let inventory) = await f.store.loadRemovalTransportInventory(held.original) else {
                throw BackendContractError.unavailable
            }
            #expect(inventory.journal.contains { OriginalUploadAcceptanceValueValidation.exact($0.mutation, record.mutation) })
            #expect(inventory.requests.isEmpty)
            let accepted = try await f.commit(f.plan([try await f.source("later-accepted")], presences: [.unknown]))
            #expect(accepted.children[0].decision == .notProcessed(.fileUnknown))
            let after = try await mediaSnapshot(f.store), reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == after)
            try await f.assertBytes(held); try await f.assertBytes(peer)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func laterInvalidationDoesNotReevaluateAnEarlierAcceptedDecision(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate), binding = try await f.source("accepted")
            let record = try await f.commit(f.plan([binding], presences: [await f.presence(binding)]))
            try await f.reserveInvalidation(binding)
            let reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened).originalUploadAcceptances == [record])
            #expect(record.children[0].decision == .accepted)
            #expect(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
            try await f.assertBytes(binding)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func opaqueCaptureBytesRemainExactAndAnAliasCannotBorrowTheSavedBinding(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate)
            let composed = try await f.source("composed", capture: "capture-\u{00e9}")
            let spaced = try await f.source("spaced", capture: "  opaque capture  ")
            let alias = OriginalBinding(original: .init(capture: .init(rawValue: "capture-e\u{0301}"),
                generation: composed.original.generation, content: composed.original.content), reference: composed.reference,
                saveRecord: composed.saveRecord, saveCommit: composed.saveCommit)
            let rejected = try await f.commit(f.plan([alias], presences: [await f.presence(composed)]))
            #expect(rejected.children[0].decision == .notProcessed(.bindingUnavailable))
            #expect(try await mediaSnapshot(f.store).requests.isEmpty)
            let record = try await f.commit(f.plan([composed, spaced], presences: [await f.presence(composed), await f.presence(spaced)]))
            #expect(record.children.map(\.decision) == [.accepted, .accepted])
            #expect(record.plan.request.targets[1].binding.original.capture.rawValue.utf8.elementsEqual("  opaque capture  ".utf8))
            let after = try await mediaSnapshot(f.store), reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == after)
            try await f.assertBytes(composed); try await f.assertBytes(spaced)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func personParentAndChildReservationsRejectUploadIDsInBothOrders(candidate: StorageCandidate, personFirst: Bool) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate)
            let upload = try await f.source("upload"), other = try await f.source("person")
            let request = try await f.legacyRequest(other)
            let personParent = MediaOperationID(rawValue: "person-parent-\u{00e9}"), personChild = MediaOperationID(rawValue: "person-child-\u{00e9}")
            let uploadParent = MediaOperationID(rawValue: "upload-parent-\u{00e9}"), uploadChild = MediaOperationID(rawValue: "upload-child-\u{00e9}")
            if personFirst {
                let person = try f.person(request, parent: personParent, child: personChild)
                _ = try await f.backend(.personControl(person))
                let before = try await mediaSnapshot(f.store)
                for alias in ["person-parent-e\u{0301}", "person-child-e\u{0301}"] {
                    for parentCollision in [false, true] {
                        let plan = try f.plan([upload], presences: [.missing], parent: parentCollision ? alias : UUID().uuidString,
                            operations: [.init(rawValue: parentCollision ? UUID().uuidString : alias)])
                        #expect(await f.store.commit(try await f.mutation(plan)) == .rejected(.identityMismatch))
                    }
                }
                #expect(try await mediaSnapshot(f.store) == before)
                _ = try await f.commit(f.plan([upload], presences: [.missing], parent: uploadParent.rawValue, operations: [uploadChild]))
            } else {
                let record = try await f.commit(f.plan([upload], presences: [.missing], parent: uploadParent.rawValue, operations: [uploadChild]))
                #expect(record.children[0].decision == .notProcessed(.fileMissing))
                let before = try await mediaSnapshot(f.store)
                for alias in ["upload-parent-e\u{0301}", "upload-child-e\u{0301}"] {
                    for parentCollision in [false, true] {
                        let person = try f.person(request, parent: .init(rawValue: parentCollision ? alias : UUID().uuidString),
                            child: .init(rawValue: parentCollision ? UUID().uuidString : alias))
                        #expect(await f.store.commit(try await f.backendMutation(.personControl(person))) == .rejected(.identityMismatch))
                    }
                }
                #expect(try await mediaSnapshot(f.store) == before)
                _ = try await f.backend(.personControl(f.person(request, parent: personParent, child: personChild)))
            }
            let after = try await mediaSnapshot(f.store), reopened = try f.reopen()
            #expect(after.personControls.count == 1 && after.originalUploadAcceptances.count == 1)
            #expect(try await mediaSnapshot(reopened) == after)
            try await f.assertBytes(upload); try await f.assertBytes(other)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func legacyNestedIDsAndAllNotProcessedUploadIDsRemainReservedInBothOrders(candidate: StorageCandidate, legacyFirst: Bool) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate), binding = try await f.source("legacy")
            let operation = MediaOperationID(rawValue: "nested-\u{00e9}")
            if legacyFirst {
                let batch = try await f.transferBatch(binding, operation: operation)
                _ = try await mediaCommit(f.store, .batch(batch))
                let before = try await mediaSnapshot(f.store)
                for parentCollision in [false, true] {
                    let alias = "nested-e\u{0301}"
                    let plan = try f.plan([binding], presences: [.missing], parent: parentCollision ? alias : UUID().uuidString,
                        operations: [.init(rawValue: parentCollision ? UUID().uuidString : alias)])
                    #expect(await f.store.commit(try await f.mutation(plan)) == .rejected(.identityMismatch))
                }
                #expect(try await mediaSnapshot(f.store) == before)
                let duplicate = try await f.commit(f.plan([binding], presences: [await f.presence(binding)]))
                #expect(duplicate.children[0].decision == .notProcessed(.alreadyRequested))
                #expect(try await mediaSnapshot(f.store).batches.count == 1)
            } else {
                let plan = try f.plan([binding], presences: [.missing], parent: "parent-\u{00e9}", operations: [operation])
                _ = try await f.commit(plan)
                let before = try await mediaSnapshot(f.store)
                for alias in ["parent-e\u{0301}", "nested-e\u{0301}"] {
                    let batch = try await f.transferBatch(binding, operation: .init(rawValue: alias))
                    #expect(await f.store.commit(.init(expectedRevision: batch.expectedRevision, change: .batch(batch))) == .rejected(.identityMismatch))
                }
                #expect(try await mediaSnapshot(f.store) == before)
                let safe = try await f.transferBatch(binding, operation: .init(rawValue: UUID().uuidString))
                _ = try await mediaCommit(f.store, .batch(safe))
            }
            let after = try await mediaSnapshot(f.store), reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == after)
            try await f.assertBytes(binding)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func queuedPhotoChildReservationsAndUploadReservationsCannotBorrowEachOther(candidate: StorageCandidate, photoFirst: Bool) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate), binding = try await f.source("photos")
            let photo = try await UploadAcceptancePhotoFixture.make(f, binding: binding)
            let parent = MediaOperationID(rawValue: "upload-parent-\u{00e9}"), child = MediaOperationID(rawValue: "upload-child-\u{00e9}")
            if photoFirst {
                let target = try PhotoSaveBatchTarget(source: photo.source, operation: .init(rawValue: "photo-child-\u{00e9}"))
                let batch = try PhotoSaveBatch(operation: .init(rawValue: "photo-parent-\u{00e9}"), storeIdentity: f.identity, targets: [target])
                _ = try await f.backend(.photoBatch(command: batch.operation, value: .accept(batch)))
                let before = try await mediaSnapshot(f.store)
                #expect(before.photoSaveBatches[0].targets[0].status == .queued && before.photoRegistrations.isEmpty)
                for alias in ["photo-parent-e\u{0301}", "photo-child-e\u{0301}"] {
                    for parentCollision in [false, true] {
                        let plan = try f.plan([binding], presences: [.missing], parent: parentCollision ? alias : UUID().uuidString,
                            operations: [.init(rawValue: parentCollision ? UUID().uuidString : alias)])
                        #expect(await f.store.commit(try await f.mutation(plan)) == .rejected(.identityMismatch))
                    }
                }
                #expect(try await mediaSnapshot(f.store) == before)
                _ = try await f.commit(f.plan([binding], presences: [.missing], parent: parent.rawValue, operations: [child]))
                _ = try await f.backend(.photoBatch(command: target.operation, value: .beginChild(batch: batch.operation, target: target)))
                guard case .starting = try await mediaSnapshot(f.store).photoSaveBatches[0].targets[0].status else {
                    throw BackendContractError.wrongStage
                }
            } else {
                _ = try await f.commit(f.plan([binding], presences: [.missing], parent: parent.rawValue, operations: [child]))
                let before = try await mediaSnapshot(f.store)
                for alias in ["upload-parent-e\u{0301}", "upload-child-e\u{0301}"] {
                    let target = try PhotoSaveBatchTarget(source: photo.source, operation: .init(rawValue: alias))
                    let batch = try PhotoSaveBatch(operation: .init(rawValue: UUID().uuidString), storeIdentity: f.identity, targets: [target])
                    #expect(await f.store.commit(try await f.backendMutation(.photoBatch(command: batch.operation, value: .accept(batch))))
                        == .rejected(.identityMismatch))
                }
                #expect(try await mediaSnapshot(f.store) == before)
                let target = try PhotoSaveBatchTarget(source: photo.source, operation: .init(rawValue: "photo-child-safe"))
                let batch = try PhotoSaveBatch(operation: .init(rawValue: "photo-parent-safe"), storeIdentity: f.identity, targets: [target])
                _ = try await f.backend(.photoBatch(command: batch.operation, value: .accept(batch)))
                _ = try await f.backend(.photoBatch(command: target.operation, value: .notProcessed(batch: batch.operation, target: target, reason: .cancelled)))
            }
            let after = try await mediaSnapshot(f.store), reopened = try f.reopen()
            #expect(after.originalUploadAcceptances.count == 1 && after.photoSaveBatches.count == 1 && after.photoRegistrations.isEmpty)
            #expect(try await mediaSnapshot(reopened) == after)
            #expect(try Data(contentsOf: photo.mediaURL) == photo.bytes)
            try await f.assertBytes(binding)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func notProcessedChildAndParentIDsRejectLaterCommandsButAcceptedChildReferencesStillWork(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await OriginalUploadDiskFixture.make(run, candidate: candidate)
            let a = try await f.source("accepted"), b = try await f.source("unprocessed")
            let record = try await f.commit(f.plan([a, b], presences: [await f.presence(a), .missing],
                parent: "parent-\u{00e9}", operations: [.init(rawValue: "accepted-\u{00e9}"), .init(rawValue: "unprocessed-\u{00e9}")]))
            let before = try await mediaSnapshot(f.store)
            for alias in ["parent-e\u{0301}", "accepted-e\u{0301}", "unprocessed-e\u{0301}"] {
                let publication = PublishedRenditionObservation(command: .init(rawValue: alias), registration: f.registration.server.registration,
                    rendition: statusRendition(b.original), observation: .init(rawValue: 1), invalidationGeneration: .init(rawValue: 0))
                #expect(await f.store.commit(try await f.backendMutation(.publication(publication))) == .rejected(.identityMismatch))
                let request = MediaRequest(operation: .init(rawValue: alias), target: .original(b.original), purpose: .upload,
                    registration: f.registration.server.registration, expectedStartRevision: before.revision)
                #expect(await f.store.commit(try await f.backendMutation(.request(command: request.operation, value: request))) == .rejected(.identityMismatch))
            }
            #expect(try await mediaSnapshot(f.store) == before)
            let accepted = try #require(record.children[0].initialRequest)
            _ = try await mediaCommit(f.store, .requestTransition(command: .init(rawValue: UUID().uuidString), operation: accepted.operation,
                target: accepted.target, registration: accepted.registration, value: .pause))
            #expect(try await mediaSnapshot(f.store).requests[0].intent == .paused)
            #expect(await f.store.lookupCommit(record.mutation) == .committed(record.commit))
            let after = try await mediaSnapshot(f.store), reopened = try f.reopen()
            #expect(try await mediaSnapshot(reopened) == after)
            try await f.assertBytes(a); try await f.assertBytes(b)
        }
    }
}

nonisolated private enum UploadAcceptanceSaveKind { case saved, partial, unknown }

nonisolated private struct OriginalUploadDiskFixture {
    let originals: OriginalRemovalFixture
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    var store: any MediaDiskStore { originals.store }

    static func make(_ run: ExplorationRunDirectory, candidate: StorageCandidate, fault: RecordingStoreFault? = nil) async throws -> Self {
        let store: any MediaDiskStore
        switch candidate {
        case .atomicFile: store = try AtomicFileRecordingStore(run: run, mode: .createNew, fault: fault, supportedVerificationSchemas: ["s32-contract"])
        case .sqlite: store = try SQLiteRecordingStore(run: run, mode: .createNew, fault: fault, supportedVerificationSchemas: ["s32-contract"])
        }
        let files = ManagedOriginalStore(run: run), access = ManagedOriginalAccess(store: store, originals: files)
        let originals = OriginalRemovalFixture(run: run, store: store, files: files, access: access, candidate: candidate)
        let registration = try await inventoryRegister(store)
        return .init(originals: originals, identity: try #require(try await mediaSnapshot(store).storeIdentity), registration: registration)
    }

    func source(_ name: String, kind: UploadAcceptanceSaveKind = .saved, capture: String? = nil) async throws -> OriginalBinding {
        let f = try CaptureFixture(clip: name + "-" + UUID().uuidString)
        let context = CaptureContext(generation: f.context.generation, capture: .init(rawValue: capture ?? f.context.capture.rawValue))
        let intent = RecordingIntent(context: context, operation: f.intent.operation, original: f.intent.original,
            trialReference: f.intent.trialReference, desired: f.desired, applied: f.applied, acceptedAt: f.time)
        let first = CaptureCommandToken(context: context, operation: intent.operation, ordinal: 1)
        let last = CaptureCommandToken(context: context, operation: intent.operation, ordinal: 4)
        guard case .committed(let intentCommit) = await store.execute(.commitIntent(first, expectedRevision: 0, intent)) else {
            throw BackendContractError.notCommitted
        }
        let url = try await originals.files.reserve(original: intent.original)
        try await SyntheticMovieFixture.write(to: url, withAudio: true)
        let digest = try await originals.files.digest(for: intent.original)
        var save = try RecordingSaveLifecycle(intent: intent, intentToken: first, revision: 0)
        try save.acceptIntentCommit(intentCommit)
        try save.acceptRecordingEnd(context: context, evidence: f.end)
        try save.acceptFile(.init(context: context, original: intent.original, byteCount: digest.byteCount, finalizedAt: f.time))
        let observed = f.inspection()
        let completeness: CaptureMediaCompleteness
        switch kind {
        case .saved: completeness = .complete
        case .partial: completeness = .partial(.resourceUnavailable)
        case .unknown: completeness = .unknown(.notMeasured)
        }
        // Deliberate saved-classification inputs over a real synthetic MOV.
        // Native H264 is not relabelled as a formal camera/Log producer.
        let inspection = CaptureMediaInspection(context: context, original: intent.original, video: observed.video, audio: observed.audio,
            format: observed.format, playback: observed.playback, completeness: completeness)
        _ = try save.acceptInspection(inspection, resultToken: last)
        let record = try #require(save.resultRecord)
        guard case .committed(let receipt) = await store.execute(.commitResult(last, expectedRevision: 1, record)) else {
            throw BackendContractError.notCommitted
        }
        let binding = OriginalBinding(original: .init(capture: context.capture, generation: .init(rawValue: 1),
            content: try .init(byteCount: digest.byteCount, algorithm: "sha256", digest: digest.sha256)),
            reference: intent.original, saveRecord: record, saveCommit: receipt)
        _ = try await mediaOriginalCommit(store, .bind(binding))
        return binding
    }

    func presence(_ binding: OriginalBinding) async -> OriginalUploadFilePresence {
        switch await originals.files.observeFile(binding.reference) {
        case .present(let bytes): .present(byteCount: bytes)
        case .absent: .missing
        case .unavailable: .inaccessible
        }
    }
    func plan(_ bindings: [OriginalBinding], presences: [OriginalUploadFilePresence], parent: String = UUID().uuidString,
        operations: [MediaOperationID]? = nil, registration: DeviceRegistration? = nil,
        identity: RegistrationStoreIdentity? = nil) throws -> OriginalUploadAcceptancePlan {
        let operations = operations ?? bindings.map { _ in MediaOperationID(rawValue: UUID().uuidString) }
        guard operations.count == bindings.count else { throw BackendContractError.invalidValue }
        let request = try OriginalUploadAcceptanceRequest(parent: .init(rawValue: parent), storeIdentity: identity ?? self.identity,
            registration: registration ?? self.registration, scope: bindings.count == 1 ? .single : .multiple,
            targets: zip(operations, bindings).map { .init(operation: $0.0, binding: $0.1) })
        return try .init(request: request, presences: presences)
    }
    func mutation(_ plan: OriginalUploadAcceptancePlan) async throws -> BackendStoreMutation {
        .init(expectedRevision: try await mediaSnapshot(store).revision, change: .originalUploadAcceptance(plan),
            expectedStoreIdentity: plan.request.storeIdentity)
    }
    func commit(_ plan: OriginalUploadAcceptancePlan) async throws -> StoredOriginalUploadAcceptance {
        let mutation = try await mutation(plan)
        guard case .committed(let receipt) = await store.commit(mutation), await store.lookupCommit(mutation) == .committed(receipt) else {
            throw BackendContractError.notCommitted
        }
        let record = try #require(try await mediaSnapshot(store).originalUploadAcceptances.last)
        guard record.isCommitted, OriginalUploadAcceptanceValueValidation.exact(record.mutation, mutation) else {
            throw BackendContractError.identityMismatch
        }
        return record
    }
    func backendMutation(_ change: BackendStoreChange) async throws -> BackendStoreMutation {
        .init(expectedRevision: try await mediaSnapshot(store).revision, change: change, expectedStoreIdentity: identity)
    }
    func backend(_ change: BackendStoreChange) async throws -> BackendCommitReceipt {
        guard case .committed(let receipt) = await store.commit(try await backendMutation(change)) else { throw BackendContractError.notCommitted }
        return receipt
    }
    func legacyRequest(_ binding: OriginalBinding) async throws -> MediaRequest {
        let request = MediaRequest(operation: .init(rawValue: UUID().uuidString), target: .original(binding.original), purpose: .upload,
            registration: registration.server.registration, expectedStartRevision: try await mediaSnapshot(store).revision)
        _ = try await backend(.request(command: request.operation, value: request))
        return try #require(try await mediaSnapshot(store).requests.last)
    }
    func person(_ request: MediaRequest, parent: MediaOperationID, child: MediaOperationID) throws -> MediaPersonControlPlan {
        try .init(parent: parent, storeIdentity: identity, scope: .single, action: .pause,
            children: [.init(command: child, target: .init(request))])
    }
    func transferBatch(_ binding: OriginalBinding, operation: MediaOperationID) async throws -> TransferBatch {
        let descriptor = OriginalDescriptor(original: binding.original, reference: binding.reference, saveResult: binding.saveRecord.result,
            saveCommit: binding.saveCommit, savedReference: binding.reference, savedContext: binding.saveRecord.intent.context,
            presence: .present, readiness: .ready)
        return try .init(id: .init(rawValue: UUID().uuidString), originals: [descriptor], operations: [operation], onWiFi: true,
            registration: registration, expectedRevision: try await mediaSnapshot(store).revision)
    }
    func reserveRemoval(_ binding: OriginalBinding) async throws {
        let batch = try originals.discardBatch(binding, name: "new-reservation-" + UUID().uuidString)
        let initial = try await mediaOriginalSnapshot(store)
        guard case .committed = await store.commitOriginal(.init(operation: batch.operation, expectedRevision: initial.revision,
            change: .removalBatch(batch))) else { throw BackendContractError.notCommitted }
        let snapshot = try await mediaOriginalSnapshot(store)
        let state = try #require(snapshot.logicalOriginals.first { OriginalUploadAcceptanceValueValidation.exact($0.original, binding.original) })
        let intent = batch.intent(for: batch.targets[0])
        guard case .committed = await store.commitOriginal(.init(operation: intent.operation, expectedRevision: snapshot.revision,
            change: .reserveRemoval(intent, expectedInvalidation: state.invalidationGeneration, expectedAccess: state.accessGeneration))) else {
            throw BackendContractError.notCommitted
        }
    }
    func reserveInvalidation(_ binding: OriginalBinding) async throws {
        let rendition = statusRendition(binding.original)
        _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration.server.registration)))
        _ = try await mediaOriginalCommit(store, .reserveInvalidation(.init(statusInvalidation(rendition,
            registration: registration.server.registration, id: "new-invalidation-" + UUID().uuidString))))
    }
    func reopen() throws -> any MediaDiskStore { try OriginalRemovalFixture.open(originals.run, candidate: originals.candidate) }
    func assertBytes(_ binding: OriginalBinding) async throws {
        let digest = try await originals.files.digest(for: binding.reference)
        #expect(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
    }
}

nonisolated private func uploadChangedBinding(_ binding: OriginalBinding, field: String) throws -> OriginalBinding {
    let record = binding.saveRecord
    let context = CaptureContext(generation: record.intent.context.generation, capture: .init(rawValue: "changed-capture"))
    let changedIntent = RecordingIntent(context: field == "record-context" ? context : record.intent.context,
        operation: record.intent.operation, original: record.intent.original, trialReference: record.intent.trialReference,
        desired: record.intent.desired, applied: record.intent.applied, acceptedAt: record.intent.acceptedAt, capturedAt: record.intent.capturedAt)
    let changedRecord = RecordingResultRecord(intent: changedIntent, end: record.end, file: record.file, inspection: record.inspection, result: record.result)
    let changedCommit = RecordingCommitReceipt(token: binding.saveCommit.token, previousRevision: 11, committedRevision: 12)
    return .init(original: field == "content" ? .init(capture: binding.original.capture, generation: .init(rawValue: 2), content: binding.original.content) : binding.original,
        reference: field == "reference" ? .init(rawValue: "different-reference") : binding.reference,
        saveRecord: changedRecord, saveCommit: field == "save-commit" ? changedCommit : binding.saveCommit)
}

nonisolated private struct UploadAcceptancePhotoFixture {
    let temporary: ManagedTemporaryMedia
    let scope: RenditionMediaScope
    let source: PhotoSaveSource
    let mediaURL: URL
    let bytes: Data
    static func make(_ f: OriginalUploadDiskFixture, binding: OriginalBinding) async throws -> Self {
        let bytes = Data((0..<1024).map { UInt8($0 % 251) }), content = try renditionContent(bytes)
        let rendition = RenditionIdentity(original: binding.original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "no-quality-proof",
            transformAssetVersion: "fixture-only", outputConfigurationIdentity: "fixture", conversionVersion: "fixture",
            rendition: .init(rawValue: UUID().uuidString.lowercased()), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(f.store, .publication(mediaPublication(rendition, registration: f.registration.server.registration)))
        let operation = MediaOperationID(rawValue: "technical-distribution-" + UUID().uuidString)
        let proof = DistributionReceipt(operation: operation, rendition: rendition, registration: f.registration.server.registration,
            commit: .init(key: .distribution(operation, rendition, f.registration.server.registration), previousRevision: 0, committedRevision: 1))
        let retrieve = RetrieveMediaCommand(gate: .init(operation: .init(rawValue: "technical-read"), attempt: .init(rawValue: "technical-attempt"),
            target: .rendition(rendition), registration: f.registration.server.registration, generation: 1), distribution: proof, range: nil)
        let leases = RenditionReadLeases(store: f.store)
        let scope = try await RenditionMediaScope.open(original: binding.original, leases: leases)
        let root = f.originals.run.url.appendingPathComponent("new-upload-photo-" + UUID().uuidString, isDirectory: true)
        let temporary = try await ManagedTemporaryMedia.open(root: root, leases: leases, scope: scope)
        let created = try await temporary.create(command: retrieve, id: .init(rawValue: UUID().uuidString),
            usageID: .init(rawValue: UUID().uuidString), capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
        try await temporary.store(bytes, range: .init(lowerBound: 0, upperBound: UInt64(bytes.count)), using: created.usage)
        _ = try await temporary.verify(created.usage)
        let state = try await temporary.stateFor(created.id)
        let source = PhotoSaveSource(storeIdentity: f.identity, registration: f.registration.server.registration, rendition: rendition,
            media: state.id, capturedAt: state.capturedAt, directoryIdentity: state.directoryIdentity, fileIdentity: try #require(state.fileIdentity),
            leaf: state.leaf, contentType: state.contentType)
        return .init(temporary: temporary, scope: scope, source: source, mediaURL: root.appendingPathComponent(state.leaf), bytes: bytes)
    }
}
