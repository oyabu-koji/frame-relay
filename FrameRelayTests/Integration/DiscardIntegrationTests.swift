import Foundation
import Testing
@testable import FrameRelay

struct DiscardIntegrationTests {
    @Test(arguments: StorageCandidate.allCases, [false, true])
    func untransferredAndUnknownOriginalsDiscardWithoutPromotingSaveOrRemoteFacts(candidate: StorageCandidate, unknown: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run, candidate: candidate)
            let target = try await fixture.original("untransferred", unknown: unknown)
            let other = try await fixture.original("untouched")
            let otherURL = try await fixture.files.existingURL(for: other.reference)
            let otherBytes = try Data(contentsOf: otherURL)
            let external = run.url.deletingLastPathComponent().appendingPathComponent("discard-external-" + UUID().uuidString)
            let externalBytes = Data("outside managed originals".utf8)
            try externalBytes.write(to: external, options: .withoutOverwriting)
            let before = try await mediaSnapshot(fixture.store)
            #expect(before.registrations.isEmpty && before.requests.isEmpty)
            #expect(before.verifications.isEmpty && before.confirmations.isEmpty && before.photoRegistrations.isEmpty)
            let reader = LibraryStoreReader(store: fixture.store, files: fixture.files)
            guard case .loaded(let priorLibrary) = await reader.loadLibrary() else {
                Issue.record("Expected original library before discard"); return
            }
            #expect(priorLibrary.history.isEmpty)
            let batch = try fixture.discardBatch(target)
            guard case .succeeded(let result) = await fixture.discardCoordinator().start(batch) else {
                Issue.record("An untransferred bound original should be discardable"); return
            }
            #expect(result.batch.authorization == .discardRiskAcknowledged(batch.targets[0]))
            #expect(result.targets.map(\.status) == [.resolved(.removed)])
            #expect(await fixture.files.observeFile(target.reference) == .absent)
            #expect(try Data(contentsOf: otherURL) == otherBytes)
            #expect(try Data(contentsOf: external) == externalBytes)
            try ExplorationRunDirectory.requireRegularFile(run.url.appendingPathComponent(target.reference.rawValue + ".reservation"))
            discardBackendFactsUnchanged(before, try await mediaSnapshot(fixture.store))
            let original = try #require(try await mediaOriginalSnapshot(fixture.store).originals.first(where: { $0.binding.original == target.original }))
            #expect(original.binding == target)
            #expect(original.binding.saveRecord.result == target.saveRecord.result)
            guard case .loaded(let library) = await reader.loadLibrary() else {
                Issue.record("Expected recorded discard history"); return
            }
            #expect(library.history.map(\.id) == [target.original.capture])
            #expect(library.recordings.map(\.id) == [other.original.capture])
            #expect(library.history.first?.recording.result == target.saveRecord)
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: candidate)
            #expect(try await mediaOriginalSnapshot(reopened).removalBatches == [result])
            #expect(try await mediaOriginalSnapshot(reopened).originals.first(where: { $0.binding.original == target.original })?.binding == target)
        }
    }

    @Test(arguments: ["no-risk", "different-target", "multiple"])
    func malformedDecodedRiskOrMultipleTargetsAreRejectedBeforeAnyIntent(kind: String) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let a = try await fixture.original("risk-a")
            let b = try await fixture.original("risk-b")
            let batch = try fixture.discardBatch(a)
            let other = try fixture.discardBatch(b, name: "different-target")
            var object = try #require(try discardJSONObject(batch) as? [String: Any])
            switch kind {
            case "no-risk": object["authorization"] = try discardJSONObject(OriginalRemovalAuthorization.cleanup)
            case "different-target": object["authorization"] = try discardJSONObject(OriginalRemovalAuthorization.discardRiskAcknowledged(other.targets[0]))
            default: object["targets"] = try [discardJSONObject(batch.targets[0]), discardJSONObject(other.targets[0])]
            }
            // Codable synthesis is intentionally exercised so the use-case must
            // revalidate values even if the checked initializer was bypassed.
            let invalid = try JSONDecoder().decode(OriginalRemovalBatch.self, from: JSONSerialization.data(withJSONObject: object))
            let before = try await mediaOriginalSnapshot(fixture.store)
            let coordinator = fixture.discardCoordinator()
            #expect(await coordinator.start(invalid) == .failed(.rejected))
            #expect(await coordinator.start(try fixture.batch([a])) == .notExecuted)
            #expect(try await mediaOriginalSnapshot(fixture.store) == before)
            #expect(await fixture.files.observeFile(a.reference) == .present(byteCount: a.original.content.byteCount))
            #expect(await fixture.files.observeFile(b.reference) == .present(byteCount: b.original.content.byteCount))
        }
    }

    @Test func exactReplayDoesNotDeleteAnotherTargetOrReexecuteAfterReopen() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let a = try await fixture.original("once-a")
            let b = try await fixture.original("keep-b")
            let batch = try fixture.discardBatch(a)
            let coordinator = fixture.discardCoordinator()
            guard case .succeeded(let result) = await coordinator.start(batch) else {
                Issue.record("Expected first exact discard"); return
            }
            let after = try await mediaOriginalSnapshot(fixture.store)
            #expect(await coordinator.start(batch) == .succeeded(result))
            #expect(await coordinator.start(try fixture.discardBatch(b)) == .failed(.rejected))
            #expect(try await mediaOriginalSnapshot(fixture.store) == after)
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: .sqlite)
            let access = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            let restored = fixture.discardCoordinator(store: reopened, access: access)
            #expect(await restored.start(batch) == .succeeded(result))
            #expect(try await mediaOriginalSnapshot(reopened).revision == after.revision)
            #expect(await fixture.files.observeFile(b.reference) == .present(byteCount: b.original.content.byteCount))
        }
    }

    @Test func invalidationOrdersWithDiscardAndKeepsMacAndPhotoHistoryUnchanged() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("invalidated-discard")
            let (_, invalidation) = try await fixture.evidence(binding)
            let archivedPhoto = try await discardSyntheticPhotoHistory(fixture, binding: binding, rendition: invalidation.rendition,
                registration: invalidation.registration)
            let macSentinel = run.url.deletingLastPathComponent().appendingPathComponent("synthetic-mac-copy-" + UUID().uuidString)
            let photosSentinel = run.url.deletingLastPathComponent().appendingPathComponent("synthetic-photos-copy-" + UUID().uuidString)
            let movie = try await fixture.files.existingURL(for: binding.reference)
            let bytes = try Data(contentsOf: movie)
            try bytes.write(to: macSentinel, options: .withoutOverwriting)
            try bytes.write(to: photosSentinel, options: .withoutOverwriting)
            guard case .succeeded(let permit) = await fixture.access.reserveInvalidation(invalidation) else {
                Issue.record("Expected exact invalidation reservation"); return
            }
            guard case .succeeded(let blocked) = await fixture.discardCoordinator().start(try fixture.discardBatch(binding, name: "blocked-by-invalidation")) else {
                Issue.record("Pending invalidation should retain an unexecuted discard"); return
            }
            #expect(blocked.targets.first?.status == .notExecuted(.ineligible))
            #expect(try Data(contentsOf: movie) == bytes)
            try await mediaReconcile(fixture.store, original: binding.original)
            _ = try await mediaCommit(fixture.store, .invalidation(invalidation, permit))
            let before = try await mediaSnapshot(fixture.store)
            #expect(before.confirmationStates.first?.validConfirmation == nil)
            #expect(before.photoRegistrations == [archivedPhoto])
            let batch = try fixture.discardBatch(binding, name: "explicit-after-invalidation")
            guard case .succeeded(let result) = await fixture.discardCoordinator().start(batch) else {
                Issue.record("Invalidated verification/confirmation is not required for discard"); return
            }
            #expect(result.targets.first?.status == .resolved(.removed))
            let after = try await mediaSnapshot(fixture.store)
            discardBackendFactsUnchanged(before, after)
            #expect(after.confirmationStates.first?.validConfirmation == nil)
            #expect(after.photoRegistrations == [archivedPhoto])
            #expect(try Data(contentsOf: macSentinel) == bytes)
            #expect(try Data(contentsOf: photosSentinel) == bytes)
            let state = try #require(try await mediaOriginalSnapshot(fixture.store).originals.first)
            #expect(state.binding.saveRecord == binding.saveRecord)
            #expect(state.invalidationGeneration == invalidation.generation)
            #expect(state.resolvedRemoval == batch.intent(for: batch.targets[0]))
        }
    }

    @Test func activeSDKAndOldUnknownReaderPreventDiscardUntilActualReleaseAndFreshAction() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("discard-reader", unknown: true)
            guard case .succeeded(let source) = await fixture.access.acquirePlayback(binding.original,
                operation: .init(rawValue: "discard-player"), leaseID: .init(rawValue: "discard-reader")),
                  case .succeeded(let attachment) = await fixture.access.attachReader(source.lease, id: .init(rawValue: "discard-sdk")) else {
                Issue.record("Expected real reader and SDK attachment"); return
            }
            await fixture.access.requestReaderStop(source.lease)
            #expect(await fixture.access.releaseRead(source.lease) == .inProgress)
            let batch = try fixture.discardBatch(binding)
            guard case .succeeded(let result) = await fixture.discardCoordinator().start(batch) else {
                Issue.record("Expected a durable non-execution while SDK is active"); return
            }
            #expect(result.targets.first?.status == .notExecuted(.terminationUnconfirmed))
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: .sqlite)
            let newOwner = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            #expect(await newOwner.recoverPersistedReaders(binding.original) == .unknown)
            #expect(await newOwner.reconcileReaders(binding.original) == .inProgress)
            #expect(await fixture.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            _ = await fixture.access.readerDidFinish(attachment)
            #expect(await fixture.access.releaseRead(source.lease) == .succeeded(.init(lease: source.lease)))
            #expect(await fixture.discardCoordinator().start(batch) == .succeeded(result))
            guard case .succeeded(let removed) = await fixture.discardCoordinator().start(try fixture.discardBatch(binding, name: "new-risk-confirmation")) else {
                Issue.record("Fresh explicit acknowledgement should work after actual close"); return
            }
            #expect(removed.targets.first?.status == .resolved(.removed))
            #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.binding.saveRecord == binding.saveRecord)
        }
    }

    @Test(arguments: [OriginalRemovalFaultStore.Stage.batch, .reserve, .boundary, .result], [false, true])
    @MainActor func interruptedDiscardRestoresOnlyObservedFactsAndNeverRestartsUnlink(stage: OriginalRemovalFaultStore.Stage, after: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("discard-interruption")
            let originalState = try await mediaOriginalSnapshot(fixture.store)
            let faulty = OriginalRemovalFaultStore(base: fixture.store)
            faulty.configure(stage, afterCommit: after)
            let access = ManagedOriginalAccess(store: faulty, originals: fixture.files)
            let batch = try fixture.discardBatch(binding)
            #expect(await fixture.discardCoordinator(store: faulty, access: access).start(batch) == .unknown)
            let unlinked = stage == .result || (stage == .boundary && after)
            #expect(await fixture.files.observeFile(binding.reference) == (unlinked ? .absent : .present(byteCount: binding.original.content.byteCount)))
            let beforeRecovery = try await mediaOriginalSnapshot(fixture.store)
            if stage == .batch && !after {
                #expect(beforeRecovery == originalState)
            } else if stage == .batch || (stage == .reserve && !after) {
                #expect(beforeRecovery.removalBatches.first?.targets.first?.status == .unprocessed)
            } else if stage == .result && after {
                #expect(beforeRecovery.removalBatches.first?.targets.first?.status == .resolved(.removed))
            } else {
                #expect(beforeRecovery.removalBatches.first?.targets.first?.status == .reserved(batch.intent(for: batch.targets[0])))
            }
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: .sqlite)
            let recovered = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            let recovery = OriginalRemovalReconciler(store: reopened, execution: recovered)
            guard case .succeeded(let records) = await recovery.reconcile() else {
                Issue.record("Expected local observation of the exact discard intent"); return
            }
            if stage == .batch && !after { #expect(records.isEmpty) }
            else {
                let row = try #require(records.first)
                #expect(row.batch.authorization == .discardRiskAcknowledged(batch.targets[0]))
                if unlinked { #expect(row.targets.first?.status == .resolved(.removed)) }
                else if (stage == .reserve && after) || stage == .boundary { #expect(row.targets.first?.status == .resolved(.notRemoved)) }
                else { #expect(row.targets.first?.status == .unprocessed) }
            }
            let reconciled = try await mediaOriginalSnapshot(reopened)
            _ = await recovery.reconcile()
            #expect(try await mediaOriginalSnapshot(reopened) == reconciled)
            #expect(await fixture.files.observeFile(binding.reference) == (unlinked ? .absent : .present(byteCount: binding.original.content.byteCount)))
            #expect(reconciled.originals.first?.binding.saveRecord == binding.saveRecord)
        }
    }

    @Test(arguments: [OriginalRemovalFaultStore.Stage.batch, .reserve, .result])
    @MainActor func exactLostReplyLookupAllowsOnlyOneLiveDiscard(stage: OriginalRemovalFaultStore.Stage) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("discard-exact-lookup")
            let faulty = OriginalRemovalFaultStore(base: fixture.store)
            faulty.configure(stage, afterCommit: true, hideLookup: false)
            let access = ManagedOriginalAccess(store: faulty, originals: fixture.files)
            let coordinator = fixture.discardCoordinator(store: faulty, access: access)
            let batch = try fixture.discardBatch(binding)
            guard case .succeeded(let result) = await coordinator.start(batch) else {
                Issue.record("Exact durable lookup should reconcile the one live command"); return
            }
            #expect(result.targets.first?.status == .resolved(.removed))
            let after = try await mediaOriginalSnapshot(fixture.store)
            #expect(await coordinator.start(batch) == .succeeded(result))
            #expect(try await mediaOriginalSnapshot(fixture.store) == after)
            #expect(await fixture.files.observeFile(binding.reference) == .absent)
        }
    }
}

nonisolated private func discardJSONObject<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}

nonisolated private func discardBackendFactsUnchanged(_ before: BackendStoreSnapshot, _ after: BackendStoreSnapshot) {
    #expect(after.registrationIntents == before.registrationIntents)
    #expect(after.registrations == before.registrations)
    #expect(after.requests == before.requests && after.batches == before.batches)
    #expect(after.verifications == before.verifications && after.confirmations == before.confirmations)
    #expect(after.invalidations == before.invalidations && after.publications == before.publications)
    #expect(after.photoRegistrations == before.photoRegistrations && after.temporaryMedia == before.temporaryMedia)
    #expect(after.outbox == before.outbox && after.deliveries == before.deliveries)
    #expect(after.distributionObservations == before.distributionObservations)
}

/// Real disposable temporary bytes and explicitly synthetic Photos journal input.
/// No PhotoKit API or accepted Rec.709 transformation is claimed by this helper.
nonisolated private func discardSyntheticPhotoHistory(_ fixture: OriginalRemovalFixture, binding: OriginalBinding,
    rendition: RenditionIdentity, registration: RegistrationIdentity) async throws -> PhotoRegistrationRecord {
    let sourceURL = try await fixture.files.existingURL(for: binding.reference)
    let bytes = try Data(contentsOf: sourceURL)
    let operation = MediaOperationID(rawValue: "discard-photo-distribution")
    let distribution = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
        commit: backendCommit(.distribution(operation, rendition, registration), revision: 0))
    let command = RetrieveMediaCommand(gate: .init(operation: .init(rawValue: "discard-photo-read"),
        attempt: .init(rawValue: "discard-photo-attempt"), target: .rendition(rendition), registration: registration,
        generation: 1), distribution: distribution, range: nil)
    let leases = RenditionReadLeases(store: fixture.store)
    let scope = try await RenditionMediaScope.open(original: rendition.original, leases: leases)
    let temporary = try await ManagedTemporaryMedia.open(root: fixture.run.url.appendingPathComponent("discard-photo-temporary"), leases: leases, scope: scope)
    let receipt = try await temporary.create(command: command, id: .init(rawValue: "discard-photo-media"),
        usageID: .init(rawValue: "discard-photo-download"), capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
    try await temporary.store(bytes, range: .init(lowerBound: 0, upperBound: UInt64(bytes.count)), using: receipt.usage)
    _ = try await temporary.verify(receipt.usage)
    guard case .succeeded(let photo) = await temporary.acquireUsage(receipt.id, purpose: .photoHandoff,
        usageID: .init(rawValue: "discard-photo-use")) else { throw BackendContractError.ineligibleOriginal }
    #expect(await temporary.releaseUsage(receipt.usage) == .succeeded(receipt.id))
    let state = try await temporary.stateFor(receipt.id)
    let intent = try PhotoRegistrationIntent(operation: .init(rawValue: "discard-photo-intent"),
        handoff: state.receipt(for: photo).photoHandoff(expected: rendition))
    _ = try await mediaCommit(fixture.store, .photo(command: intent.operation, value: .intent(intent)))
    _ = try await mediaCommit(fixture.store, .photo(command: .init(rawValue: "discard-photo-success"),
        value: .result(.init(intent: intent, outcome: .succeeded(localIdentifier: try .init(rawValue: "synthetic-existing-photo"))))))
    #expect(await temporary.releaseUsage(photo) == .succeeded(receipt.id))
    _ = try await scope.close()
    return try #require(try await mediaSnapshot(fixture.store).photoRegistrations.last)
}
