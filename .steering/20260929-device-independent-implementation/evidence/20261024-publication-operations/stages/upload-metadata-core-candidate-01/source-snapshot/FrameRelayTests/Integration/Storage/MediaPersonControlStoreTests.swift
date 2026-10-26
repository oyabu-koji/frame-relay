import Foundation
import Testing
@testable import FrameRelay

/// Each case creates a new dedicated root. Existing fixture/movie/Photos bytes
/// are never removed, repaired, reseeded or used as a successful producer proof.
struct MediaPersonControlStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func atomicFixedAllPausePersistsParentReasonsWaitsAndExcludesLaterRequests(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PersonControlDiskFixture.make(run, candidate: candidate)
            let a = try await f.request("first"), b = try await f.request("completed-race")
            try await f.transition(a, .wait(.wiFiUnavailable, active: true))
            try await f.transition(a, .wait(.saving, active: true))
            let plan = try f.plan([a, b], action: .pause, scope: .allPause)
            let later = try await f.request("later-not-in-fixed-set")
            try await f.transition(b, .reconciled(.init(context: .init(operation: b.operation, registration: b.registration,
                target: b.target, session: nil), observation: .init(rawValue: 1), result: .succeeded(.init(rawValue: "known-external-completion")))))
            let before = await f.store.loadRemovalTransportInventory(f.binding.original)
            let record = try await f.commit(plan)
            #expect(record.children.map(\.decision) == [.recorded, .notProcessed(.completed)])
            let after = try await mediaSnapshot(f.store)
            #expect(after.requests.first { $0.operation == a.operation }?.intent == .paused)
            #expect(after.requests.first { $0.operation == a.operation }?.waits == [.wiFiUnavailable, .saving])
            #expect(after.requests.first { $0.operation == b.operation }?.intent == .running)
            #expect(after.requests.first { $0.operation == later.operation }?.intent == .running)
            #expect(after.personControls == [record] && after.personControls[0].plan.children.count == 2)
            let inventory = await f.store.loadRemovalTransportInventory(f.binding.original)
            #expect(inventory != before)
            guard case .succeeded(let actual) = inventory else { throw BackendContractError.unavailable }
            #expect(actual.journal.contains { MediaPersonControlValueValidation.exact($0.mutation, record.mutation) })
            let reopened = try OriginalRemovalFixture.open(run, candidate: candidate)
            #expect(try await mediaSnapshot(reopened) == after)
            #expect(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
            try await f.assertOriginalUnchanged()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func resumeIntentRetainsEnvironmentWaitsAndCancellationCannotBeRevived(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PersonControlDiskFixture.make(run, candidate: candidate), request = try await f.request("compound-waits")
            try await f.transition(request, .wait(.recording, active: true))
            try await f.transition(request, .wait(.saving, active: true))
            try await f.transition(request, .wait(.wiFiUnavailable, active: true))
            _ = try await f.commit(f.plan([request], action: .pause))
            let resumed = try await f.commit(f.plan([request], action: .resumeIntent))
            #expect(resumed.children[0].decision == .recorded)
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.requests[0].intent == .running && snapshot.requests[0].waits == [.recording, .saving, .wiFiUnavailable])
            #expect(snapshot.requests[0].transport == .queued && snapshot.backgroundTasks.isEmpty)
            _ = try await f.commit(f.plan([request], action: .cancel))
            let forbidden = try await f.commit(f.plan([request], action: .resumeIntent))
            #expect(forbidden.children[0].decision == .notProcessed(.cancelled))
            // Old transition payloads still replay with their old no-op pause semantics.
            try await f.transition(request, .pause)
            let reopened = try OriginalRemovalFixture.open(run, candidate: candidate)
            #expect(try await mediaSnapshot(reopened).requests[0].intent == .cancelled)
            #expect(try await mediaSnapshot(reopened).personControls.last == forbidden)
            try await f.assertOriginalUnchanged()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func wrongUUIDReusedIDsAndUnicodeAliasesNeverBorrowAnEarlierControl(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PersonControlDiskFixture.make(run, candidate: candidate), request = try await f.request("request-\u{00e9}")
            let child = MediaPersonControlChild(command: .init(rawValue: "child-\u{00e9}"), target: .init(request))
            let plan = try MediaPersonControlPlan(parent: .init(rawValue: "parent-\u{00e9}"), storeIdentity: f.identity,
                scope: .single, action: .pause, children: [child])
            let mutation = try await f.mutation(plan)
            #expect(await f.store.commit(.init(expectedRevision: mutation.expectedRevision, change: .personControl(plan))) == .rejected(.identityMismatch))
            let wrong = try MediaPersonControlPlan(parent: plan.parent, storeIdentity: .init(rawValue: UUID()), scope: .single,
                action: .pause, children: [child])
            #expect(await f.store.commit(try await f.mutation(wrong)) == .rejected(.identityMismatch))
            let record = try await f.commit(plan)
            let alias = try MediaPersonControlPlan(parent: .init(rawValue: "parent-e\u{0301}"), storeIdentity: f.identity,
                scope: .single, action: .pause, children: [child])
            let aliasMutation = BackendStoreMutation(expectedRevision: record.commit.previousRevision,
                change: .personControl(alias), expectedStoreIdentity: f.identity)
            #expect(await f.store.lookupCommit(aliasMutation) == .rejected(.identityMismatch))
            let changed = try MediaPersonControlPlan(parent: plan.parent, storeIdentity: f.identity, scope: .single,
                action: .cancel, children: [child])
            #expect(await f.store.commit(try await f.mutation(changed)) == .rejected(.identityMismatch))
            let reused = try MediaPersonControlPlan(parent: .init(rawValue: "different-parent"), storeIdentity: f.identity, scope: .single,
                action: .cancel, children: [.init(command: .init(rawValue: "child-e\u{0301}"), target: .init(request))])
            #expect(await f.store.commit(try await f.mutation(reused)) == .rejected(.identityMismatch))
            let aliasSource = MediaPersonControlTarget(operation: .init(rawValue: "request-e\u{0301}"), target: request.target,
                purpose: request.purpose, registration: request.registration, expectedStartRevision: request.expectedStartRevision, attempt: request.attempt)
            let sourceAliasPlan = try MediaPersonControlPlan(parent: .init(rawValue: UUID().uuidString), storeIdentity: f.identity,
                scope: .single, action: .cancel, children: [.init(command: .init(rawValue: UUID().uuidString), target: aliasSource)])
            let sourceAliasResult = try await f.commit(sourceAliasPlan)
            #expect(sourceAliasResult.children[0].decision == .notProcessed(.identityChanged))
            let legacy = BackendStoreChange.requestTransition(command: child.command, operation: request.operation,
                target: request.target, registration: request.registration, value: .cancel)
            #expect(await f.store.commit(.init(expectedRevision: try await mediaSnapshot(f.store).revision, change: legacy)) == .rejected(.identityMismatch))
            #expect(try await mediaSnapshot(f.store).requests[0].intent == .paused)
            try await f.assertOriginalUnchanged()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func everyFixedSourceFieldIsCheckedAndOldRegistrationStopsNeverRebind(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PersonControlDiskFixture.make(run, candidate: candidate), request = try await f.request("source-check")
            for field in ["operation", "target", "registration", "purpose", "start", "attempt"] {
                let source = try personChangedTarget(.init(request), field: field)
                let plan = try MediaPersonControlPlan(parent: .init(rawValue: UUID().uuidString), storeIdentity: f.identity,
                    scope: .single, action: .pause, children: [.init(command: .init(rawValue: UUID().uuidString), target: source)])
                let record = try await f.commit(plan)
                #expect(record.children[0].decision == .notProcessed(field == "operation" ? .missingRequest : .identityChanged))
                #expect(try await mediaSnapshot(f.store).requests[0].intent == .running)
            }
            let newer = RegistrationIdentity(destination: f.registration.destination, id: .init(rawValue: UUID().uuidString.lowercased()),
                generation: .init(rawValue: f.registration.generation.rawValue + 1))
            _ = try await mediaRegister(f.store, registration: newer)
            let oldPause = try await f.commit(f.plan([request], action: .pause))
            #expect(oldPause.children[0].decision == .recorded)
            #expect(try await mediaSnapshot(f.store).requests[0].registration == f.registration)
            let oldResume = try await f.commit(f.plan([request], action: .resumeIntent))
            #expect(oldResume.children[0].decision == .notProcessed(.registrationChanged))
            #expect(try await mediaSnapshot(f.store).requests[0].intent == .paused)
            let replay = try OriginalRemovalFixture.open(run, candidate: candidate)
            #expect(try await mediaSnapshot(replay).personControls == (try await mediaSnapshot(f.store)).personControls)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func legacyBatchNestedOperationsAndPersonCommandsCannotBorrowInEitherOrder(candidate: StorageCandidate, batchFirst: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PersonControlDiskFixture.make(run, candidate: candidate)
            let request = try await f.request("person-target")
            let parent = MediaOperationID(rawValue: "person-parent-\u{00e9}"), child = MediaOperationID(rawValue: "person-child-\u{00e9}")
            if batchFirst {
                let batch = try await f.transferBatch(operation: parent)
                _ = try await mediaCommit(f.store, .batch(batch))
                let accepted = try await mediaSnapshot(f.store)
                for parentCollision in [false, true] {
                    let alias = MediaOperationID(rawValue: "person-parent-e\u{0301}")
                    let plan = try MediaPersonControlPlan(parent: parentCollision ? alias : .init(rawValue: UUID().uuidString),
                        storeIdentity: f.identity, scope: .single, action: .pause,
                        children: [.init(command: parentCollision ? child : alias, target: .init(request))])
                    #expect(await f.store.commit(try await f.mutation(plan)) == .rejected(.identityMismatch))
                }
                #expect(try await mediaSnapshot(f.store) == accepted)
                // The existing operation remains a valid target reference; it
                // is not a newly introduced parent or command.
                let source = try #require(accepted.requests.first { $0.operation == parent })
                _ = try await f.commit(f.plan([source], action: .pause))
            } else {
                let plan = try MediaPersonControlPlan(parent: parent, storeIdentity: f.identity, scope: .single, action: .pause,
                    children: [.init(command: child, target: .init(request))])
                _ = try await f.commit(plan)
                let accepted = try await mediaSnapshot(f.store)
                for alias in ["person-parent-e\u{0301}", "person-child-e\u{0301}"] {
                    let batch = try await f.transferBatch(operation: .init(rawValue: alias))
                    #expect(await f.store.commit(.init(expectedRevision: batch.expectedRevision, change: .batch(batch)))
                        == .rejected(.identityMismatch))
                }
                #expect(try await mediaSnapshot(f.store) == accepted)
                let safe = try await f.transferBatch(operation: .init(rawValue: UUID().uuidString))
                _ = try await mediaCommit(f.store, .batch(safe))
            }
            let after = try await mediaSnapshot(f.store)
            let reopened = try OriginalRemovalFixture.open(run, candidate: candidate)
            #expect(try await mediaSnapshot(reopened) == after)
            try await f.assertOriginalUnchanged()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func queuedPhotoChildrenAndPersonCommandsCannotBorrowButChildReferencesRemainValid(candidate: StorageCandidate, photoFirst: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PersonControlDiskFixture.make(run, candidate: candidate)
            let request = try await f.request("person-target")
            let photo = try await PersonControlPhotoFixture.make(f)
            let parent = MediaOperationID(rawValue: "person-parent-\u{00e9}"), child = MediaOperationID(rawValue: "person-child-\u{00e9}")
            if photoFirst {
                let target = try PhotoSaveBatchTarget(source: photo.source, operation: parent)
                let batch = try PhotoSaveBatch(operation: .init(rawValue: "photos-parent"), storeIdentity: f.identity, targets: [target])
                _ = try await f.photoCommit(command: batch.operation, .accept(batch))
                let accepted = try await mediaSnapshot(f.store)
                #expect(accepted.photoSaveBatches[0].targets[0].status == .queued)
                #expect(accepted.photoRegistrations.isEmpty)
                for parentCollision in [false, true] {
                    let alias = MediaOperationID(rawValue: "person-parent-e\u{0301}")
                    let plan = try MediaPersonControlPlan(parent: parentCollision ? alias : .init(rawValue: UUID().uuidString),
                        storeIdentity: f.identity, scope: .single, action: .pause,
                        children: [.init(command: parentCollision ? child : alias, target: .init(request))])
                    #expect(await f.store.commit(try await f.mutation(plan)) == .rejected(.identityMismatch))
                }
                #expect(try await mediaSnapshot(f.store) == accepted)
                _ = try await f.commit(f.plan([request], action: .pause))
                _ = try await f.photoCommit(command: target.operation, .beginChild(batch: batch.operation, target: target))
                guard case .starting = try await mediaSnapshot(f.store).photoSaveBatches[0].targets[0].status else {
                    throw BackendContractError.wrongStage
                }
            } else {
                let plan = try MediaPersonControlPlan(parent: parent, storeIdentity: f.identity, scope: .single, action: .pause,
                    children: [.init(command: child, target: .init(request))])
                _ = try await f.commit(plan)
                let accepted = try await mediaSnapshot(f.store)
                for alias in ["person-parent-e\u{0301}", "person-child-e\u{0301}"] {
                    let target = try PhotoSaveBatchTarget(source: photo.source, operation: .init(rawValue: alias))
                    let batch = try PhotoSaveBatch(operation: .init(rawValue: UUID().uuidString), storeIdentity: f.identity, targets: [target])
                    let mutation = try await f.photoMutation(command: batch.operation, .accept(batch))
                    #expect(await f.store.commit(mutation) == .rejected(.identityMismatch))
                }
                #expect(try await mediaSnapshot(f.store) == accepted)
                let target = try PhotoSaveBatchTarget(source: photo.source, operation: .init(rawValue: "photo-child-safe"))
                let batch = try PhotoSaveBatch(operation: .init(rawValue: "photos-parent"), storeIdentity: f.identity, targets: [target])
                _ = try await f.photoCommit(command: batch.operation, .accept(batch))
                _ = try await f.photoCommit(command: target.operation, .notProcessed(batch: batch.operation, target: target, reason: .cancelled))
                guard case .notProcessed = try await mediaSnapshot(f.store).photoSaveBatches[0].targets[0].status else {
                    throw BackendContractError.wrongStage
                }
            }
            let after = try await mediaSnapshot(f.store)
            #expect(after.personControls.count == 1 && after.photoRegistrations.isEmpty)
            let reopened = try OriginalRemovalFixture.open(run, candidate: candidate)
            #expect(try await mediaSnapshot(reopened) == after)
            #expect(try Data(contentsOf: photo.mediaURL) == photo.bytes)
            try await f.assertOriginalUnchanged()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func endedNetworkPlaybackAndInvalidatedTargetsCannotBeResumed(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PersonControlDiskFixture.make(run, candidate: candidate)
            let rendition = statusRendition(f.binding.original)
            _ = try await mediaCommit(f.store, .publication(mediaPublication(rendition, registration: f.registration)))
            let snapshot = try await mediaSnapshot(f.store)
            let playback = MediaRequest(operation: .init(rawValue: UUID().uuidString), target: .rendition(rendition), purpose: .playback,
                registration: f.registration, expectedStartRevision: snapshot.revision)
            _ = try await mediaCommit(f.store, .request(command: playback.operation, value: playback))
            try await f.transition(playback, .pause)
            try await f.transition(playback, .endPlayback)
            let ended = try await f.commit(f.plan([playback], action: .resumeIntent))
            #expect(ended.children[0].decision == .notProcessed(.playbackEnded))
            let upload = try await f.request("invalidation-blocks-resume")
            _ = try await f.commit(f.plan([upload], action: .pause))
            guard case .succeeded = await f.originals.access.reserveInvalidation(statusInvalidation(rendition, registration: f.registration)) else {
                throw BackendContractError.notCommitted
            }
            let held = try await f.commit(f.plan([upload], action: .resumeIntent))
            #expect(held.children[0].decision == .notProcessed(.targetUnavailable))
            #expect(try await mediaSnapshot(f.store).requests.first { $0.operation == upload.operation }?.intent == .paused)
            let reopened = try OriginalRemovalFixture.open(run, candidate: candidate)
            #expect(try await mediaSnapshot(reopened).personControls == (try await mediaSnapshot(f.store)).personControls)
            try await f.assertOriginalUnchanged()
        }
    }
}

nonisolated struct PersonControlDiskFixture {
    let originals: OriginalRemovalFixture
    let identity: RegistrationStoreIdentity
    let registration: RegistrationIdentity
    let binding: OriginalBinding
    var store: any MediaDiskStore { originals.store }
    static func make(_ run: ExplorationRunDirectory, candidate: StorageCandidate) async throws -> Self {
        let originals = try OriginalRemovalFixture(run: run, candidate: candidate)
        let binding = try await originals.original("person-control-" + UUID().uuidString)
        let registration = try await inventoryRegister(originals.store).server.registration
        let identity = try #require(try await mediaSnapshot(originals.store).storeIdentity)
        return .init(originals: originals, identity: identity, registration: registration, binding: binding)
    }
    func request(_ name: String) async throws -> MediaRequest {
        let snapshot = try await mediaSnapshot(store)
        let request = MediaRequest(operation: .init(rawValue: name), target: .original(binding.original), purpose: .upload,
            registration: registration, expectedStartRevision: snapshot.revision)
        _ = try await mediaCommit(store, .request(command: request.operation, value: request))
        return try #require(try await mediaSnapshot(store).requests.last)
    }
    func transferBatch(operation: MediaOperationID) async throws -> TransferBatch {
        let snapshot = try await mediaSnapshot(store)
        let registered = try #require(snapshot.registrations.last)
        let descriptor = OriginalDescriptor(original: binding.original, reference: binding.reference, saveResult: binding.saveRecord.result,
            saveCommit: binding.saveCommit, savedReference: binding.reference, savedContext: binding.saveRecord.intent.context,
            presence: .present, readiness: .ready)
        return try .init(id: .init(rawValue: UUID().uuidString), originals: [descriptor], operations: [operation], onWiFi: true,
            registration: registered, expectedRevision: snapshot.revision)
    }
    func photoMutation(command: MediaOperationID, _ value: PhotoSaveBatchChange) async throws -> BackendStoreMutation {
        .init(expectedRevision: try await mediaSnapshot(store).revision, change: .photoBatch(command: command, value: value), expectedStoreIdentity: identity)
    }
    func photoCommit(command: MediaOperationID, _ value: PhotoSaveBatchChange) async throws -> BackendCommitReceipt {
        let mutation = try await photoMutation(command: command, value)
        guard case .committed(let receipt) = await store.commit(mutation) else { throw BackendContractError.notCommitted }
        return receipt
    }
    func plan(_ requests: [MediaRequest], action: MediaPersonControlAction, scope: MediaPersonControlScope = .single) throws -> MediaPersonControlPlan {
        try .init(parent: .init(rawValue: UUID().uuidString), storeIdentity: identity, scope: scope, action: action,
            children: requests.map { .init(command: .init(rawValue: UUID().uuidString), target: .init($0)) })
    }
    func transition(_ request: MediaRequest, _ transition: MediaRequestTransition) async throws {
        _ = try await mediaCommit(store, .requestTransition(command: .init(rawValue: UUID().uuidString),
            operation: request.operation, target: request.target, registration: request.registration, value: transition))
    }
    func mutation(_ plan: MediaPersonControlPlan) async throws -> BackendStoreMutation {
        .init(expectedRevision: try await mediaSnapshot(store).revision, change: .personControl(plan), expectedStoreIdentity: plan.storeIdentity)
    }
    func commit(_ plan: MediaPersonControlPlan) async throws -> StoredMediaPersonControlPlan {
        let mutation = try await mutation(plan)
        guard case .committed(let receipt) = await store.commit(mutation), await store.lookupCommit(mutation) == .committed(receipt) else {
            throw BackendContractError.notCommitted
        }
        let record = try #require(try await mediaSnapshot(store).personControls.last)
        return record
    }
    func assertOriginalUnchanged() async throws {
        let digest = try await originals.files.digest(for: binding.reference)
        #expect(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
    }
}

/// A new-root technical source/receipt, not native Photos or a formal producer.
nonisolated private struct PersonControlPhotoFixture {
    let temporary: ManagedTemporaryMedia
    let scope: RenditionMediaScope
    let source: PhotoSaveSource
    let mediaURL: URL
    let bytes: Data

    static func make(_ f: PersonControlDiskFixture) async throws -> Self {
        let bytes = Data((0..<1024).map { UInt8($0 % 251) })
        let content = try renditionContent(bytes)
        let rendition = RenditionIdentity(original: f.binding.original, inputLogIdentity: "synthetic-not-log",
            transformAssetIdentity: "no-quality-proof", transformAssetVersion: "fixture-only", outputConfigurationIdentity: "fixture",
            conversionVersion: "fixture", rendition: .init(rawValue: UUID().uuidString.lowercased()), deliveryContent: content,
            publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(f.store, .publication(mediaPublication(rendition, registration: f.registration)))
        let operation = MediaOperationID(rawValue: "technical-distribution-" + UUID().uuidString)
        let proof = DistributionReceipt(operation: operation, rendition: rendition, registration: f.registration,
            commit: .init(key: .distribution(operation, rendition, f.registration), previousRevision: 0, committedRevision: 1))
        let retrieve = RetrieveMediaCommand(gate: .init(operation: .init(rawValue: "technical-read"), attempt: .init(rawValue: "technical-attempt"),
            target: .rendition(rendition), registration: f.registration, generation: 1), distribution: proof, range: nil)
        let leases = RenditionReadLeases(store: f.store)
        let scope = try await RenditionMediaScope.open(original: f.binding.original, leases: leases)
        let root = f.originals.run.url.appendingPathComponent("new-person-photo-" + UUID().uuidString, isDirectory: true)
        let temporary = try await ManagedTemporaryMedia.open(root: root, leases: leases, scope: scope)
        let created = try await temporary.create(command: retrieve, id: .init(rawValue: UUID().uuidString),
            usageID: .init(rawValue: UUID().uuidString), capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
        try await temporary.store(bytes, range: .init(lowerBound: 0, upperBound: UInt64(bytes.count)), using: created.usage)
        _ = try await temporary.verify(created.usage)
        let state = try await temporary.stateFor(created.id)
        let source = PhotoSaveSource(storeIdentity: f.identity, registration: f.registration, rendition: rendition,
            media: state.id, capturedAt: state.capturedAt, directoryIdentity: state.directoryIdentity, fileIdentity: try #require(state.fileIdentity),
            leaf: state.leaf, contentType: state.contentType)
        return .init(temporary: temporary, scope: scope, source: source, mediaURL: root.appendingPathComponent(state.leaf), bytes: bytes)
    }
}

nonisolated private func personChangedTarget(_ value: MediaPersonControlTarget, field: String) throws -> MediaPersonControlTarget {
    .init(operation: field == "operation" ? .init(rawValue: "missing-operation") : value.operation,
        target: field == "target" ? .original(try publicationOriginal("different-content")) : value.target,
        purpose: field == "purpose" ? .download : value.purpose,
        registration: field == "registration" ? .init(destination: value.registration.destination, id: .init(rawValue: "other"), generation: value.registration.generation) : value.registration,
        expectedStartRevision: value.expectedStartRevision + (field == "start" ? 1 : 0),
        attempt: field == "attempt" ? .init(rawValue: "different-attempt") : value.attempt)
}
