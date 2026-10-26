import Foundation
import Testing
@testable import FrameRelay

@MainActor struct ProductCleanupCompositionTests {
    @Test func normalCompositionCleansFixedEligibleTargetsAndRetainsIndependentResultsAfterReopen() async throws {
        let fixture = try await CleanupCompositionFixture.make()
        let a = try await fixture.add("cleanup-a")
        let missing = try await fixture.add("cleanup-b-missing", evidence: false)
        let b = try await fixture.add("cleanup-c")
        let keep = try await fixture.originals.original("cleanup-d-keep", unknown: true)
        let keepBytes = try Data(contentsOf: await fixture.services.originals.existingURL(for: keep.reference))
        let external = fixture.services.run.url.deletingLastPathComponent().appendingPathComponent("external.mov")
        try keepBytes.write(to: external, options: .withoutOverwriting)
        let before = try await mediaSnapshot(fixture.services.store)
        let composition = fixture.composition()
        await composition.open()
        let model = try #require(composition.library)
        let targets: Set<CaptureID> = [a.binding.original.capture, missing.binding.original.capture, b.binding.original.capture]
        #expect(model.availability(.cleanup, captures: targets) == .available)
        #expect(model.availability(.cleanup, captures: [missing.binding.original.capture]).reason != nil)
        let review = try #require(model.prepareRemovalReview(.cleanup, captures: targets))
        #expect(review.information.contains(where: { $0.contains("明示確認がありません") }))
        model.select(keep.original.capture, selected: true)
        await model.submit(review)
        #expect(model.submission?.request.targets == review.targets)
        #expect(model.submission?.request.discardRiskAcknowledged == false)
        #expect(model.submission?.phase == .awaitingRecordedResult)
        for binding in [a.binding, b.binding] {
            #expect(await fixture.services.originals.observeFile(binding.reference) == .absent)
            #expect(model.item(binding.original.capture)?.removal == .removed(.cleanup))
            #expect(model.item(binding.original.capture)?.isDiscardHistory == false)
            #expect(model.item(binding.original.capture)?.status(.retrieval).contains("オフライン再生不可") == true)
            #expect(model.item(binding.original.capture)?.operationResults.contains(where: {
                $0.id == review.id && $0.action == .cleanup && $0.outcome == .succeeded
            }) == true)
        }
        #expect(await fixture.services.originals.observeFile(missing.binding.reference) == .present(byteCount: missing.binding.original.content.byteCount))
        #expect(try Data(contentsOf: external) == keepBytes)
        #expect(try Data(contentsOf: await fixture.services.originals.existingURL(for: keep.reference)) == keepBytes)
        let after = try await mediaSnapshot(fixture.services.store)
        #expect(after.verifications == before.verifications && after.confirmations == before.confirmations)
        #expect(after.requests == before.requests && after.photoRegistrations == before.photoRegistrations)
        let reopened = try await ProductLibraryFactory(supportDirectory: fixture.parent).open()
        guard case .loaded(let library) = await reopened.reader.loadLibrary() else { throw BackendContractError.unavailable }
        #expect(library.recordings.count == 4 && library.history.isEmpty)
        let record = try #require(try await mediaOriginalSnapshot(reopened.store).removalBatches.first)
        #expect(record.batch.operation == review.id && record.batch.authorization == .cleanup)
        #expect(record.targets.map(\.target.original.capture) == review.targets.map(\.capture))
        #expect(record.targets.first(where: { $0.target.original == missing.binding.original })?.status == .notExecuted(.ineligible))
        for binding in [missing.binding, keep] {
            let digest = try await reopened.originals.digest(for: binding.reference)
            #expect(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
        }
        #expect(try await mediaOriginalSnapshot(reopened.store).logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
        try await fixture.close()
    }

    @Test func unknownFirstTransportRetainsItsSealWhileLaterCompletedChildIsReleased() async throws {
        let fixture = try await CleanupCompositionFixture.make()
        let active = try await fixture.add("cleanup-a-active", terminal: false)
        let good = try await fixture.add("cleanup-b-good")
        let composition = fixture.composition(); await composition.open()
        let model = try #require(composition.library)
        let review = try #require(model.prepareRemovalReview(.cleanup,
            captures: [active.binding.original.capture, good.binding.original.capture]))
        await model.submit(review)
        #expect(model.submission?.phase == .reconciliationRequired)
        #expect(await fixture.services.originals.observeFile(active.binding.reference) == .present(byteCount: active.binding.original.content.byteCount))
        #expect(await fixture.services.originals.observeFile(good.binding.reference) == .absent)
        let record = try #require(try await mediaOriginalSnapshot(fixture.services.store).removalBatches.first)
        #expect(record.targets.first?.status == .notExecuted(.terminationUnconfirmed))
        #expect(record.targets.last?.status == .resolved(.removed))
        let media = try #require(composition.mediaTermination)
        let goodScope = try await media.scopes.open(original: good.binding.original)
        _ = try await goodScope.close()
        #expect(await fixture.background.startUpload(active.plan) == .refused(.removalBoundaryActive))
        let counts = await fixture.sdk.counts()
        // The blocked child was never cancelled by cleanup and no task resumed.
        #expect(counts[2] == 0)
        try await fixture.complete(active)
        let operation = try #require(model.item(active.binding.original.capture)?.removalOperations.first)
        await model.reconcileRemoval(operation, capture: active.binding.original.capture)
        #expect(model.removalReconciliationMessages[operation.id]?.contains("新しい削除は実行していません") == true)
        #expect(await fixture.services.originals.observeFile(active.binding.reference) == .present(byteCount: active.binding.original.content.byteCount))
        try await fixture.close()
    }

    @Test func invalidationAfterReviewRejectsThatChildAndContinuesIndependentTarget() async throws {
        let fixture = try await CleanupCompositionFixture.make()
        let first = try await fixture.add("cleanup-a-invalidated")
        let second = try await fixture.add("cleanup-b-valid")
        let composition = fixture.composition(); await composition.open()
        let model = try #require(composition.library)
        let review = try #require(model.prepareRemovalReview(.cleanup,
            captures: [first.binding.original.capture, second.binding.original.capture]))
        let invalidation = try #require(first.invalidation)
        guard case .succeeded(let permit) = await fixture.services.access.reserveInvalidation(invalidation) else { throw BackendContractError.notCommitted }
        let media = try #require(composition.mediaTermination)
        _ = try await media.scopes.stopAndReconcile(original: first.binding.original, external: media)
        let receipt = try await mediaCommit(fixture.services.store, .invalidation(invalidation, permit))
        try await media.resume(after: .init(record: invalidation, commit: receipt))
        await model.submit(review)
        #expect(await fixture.services.originals.observeFile(first.binding.reference) == .present(byteCount: first.binding.original.content.byteCount))
        #expect(await fixture.services.originals.observeFile(second.binding.reference) == .absent)
        #expect(model.item(first.binding.original.capture)?.operationResults.first?.outcome != .succeeded)
        #expect(model.item(second.binding.original.capture)?.operationResults.first?.outcome == .succeeded)
        #expect(try await mediaSnapshot(fixture.services.store).confirmationStates.first(where: {
            $0.current.original == first.binding.original
        })?.validConfirmation == nil)
        try await fixture.close()
    }

    @Test func reopeningReservedAndUnprocessedCleanupOnlyObservesAndNeverUnlinksAgain() async throws {
        let fixture = try await CleanupCompositionFixture.make()
        let reserved = try await fixture.add("cleanup-a-reserved")
        let unprocessed = try await fixture.add("cleanup-b-unprocessed")
        let batch = try fixture.originals.batch([reserved.binding, unprocessed.binding])
        _ = try await mediaOriginalCommit(fixture.services.store, .removalBatch(batch))
        // Known test owners have terminated. Model a process lost after the
        // reservation commit, before any physical effect, using this exact row.
        try await mediaReconcile(fixture.services.store, original: reserved.binding.original)
        let backend = try await mediaSnapshot(fixture.services.store)
        let proof = try #require(backend.verifications.first(where: { $0.expected.target.original == reserved.binding.original }))
        let confirmation = try #require(backend.confirmations.first(where: { $0.intent.playback.distribution.rendition.original == reserved.binding.original }))
        let state = try #require(try await mediaOriginalSnapshot(fixture.services.store).logicalOriginals.first(where: { $0.original == reserved.binding.original }))
        _ = try await mediaOriginalCommit(fixture.services.store, .reserveCleanup(batch.intent(for: batch.targets[0]),
            .init(registration: fixture.registration, verificationCommand: proof.command, confirmationOperation: confirmation.intent.operation),
            expectedInvalidation: state.invalidationGeneration, expectedAccess: state.accessGeneration))
        let composition = fixture.composition(); await composition.open()
        let model = try #require(composition.library)
        for binding in [reserved.binding, unprocessed.binding] {
            #expect(await fixture.services.originals.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            let operation = try #require(model.item(binding.original.capture)?.removalOperations.first)
            await model.reconcileRemoval(operation, capture: binding.original.capture)
            let digest = try await fixture.services.originals.digest(for: binding.reference)
            #expect(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
        }
        let latest = try await mediaOriginalSnapshot(fixture.services.store)
        let exact = try #require(latest.removalBatches.first)
        #expect(exact.batch == batch)
        #expect(exact.targets[0].status == .resolved(.notRemoved))
        #expect(exact.targets[1].status == .notExecuted(.unavailable))
        #expect(model.snapshot?.history.isEmpty == true)
        try await fixture.close()
    }
}

/// Only tests create these synthetic remote/played/SDK facts. Real MOV content,
/// managed upload copy/FD closure, the normal writer and deletion path remain
/// real. Nothing here proves a network transfer, actual Log or Rec.709 quality.
@MainActor struct CleanupCompositionFixture {
    let parent: URL
    let library: ProductLibraryFactory
    let services: ProductLibraryServices
    let originals: OriginalRemovalFixture
    let background: ProductBackgroundMediaFactory
    let sdk: BackgroundSessionProbe
    let source: ManagedUploadSource
    let registration: RegistrationIdentity
    let identity: RegistrationStoreIdentity
    let session: BackgroundMediaSessionIdentity

    static func make(library suppliedLibrary: ProductLibraryFactory? = nil) async throws -> Self {
        let parent: URL
        let library: ProductLibraryFactory
        if let suppliedLibrary {
            library = suppliedLibrary
            parent = try await suppliedLibrary.open().run.url.deletingLastPathComponent()
        } else {
            parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FrameRelay-Cleanup-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
            library = ProductLibraryFactory(supportDirectory: parent)
        }
        let services = try await library.open()
        let originals = OriginalRemovalFixture(run: services.run, store: services.store, files: services.originals, access: services.access)
        let registration = try await mediaRegister(services.store)
        let before = try await mediaSnapshot(services.store)
        let identity = try await services.store.establishRegistrationIdentity(expectedRevision: before.revision, expectedIdentity: before.storeIdentity)
        let session = BackgroundMediaSessionIdentity(identifier: .init(rawValue: "test.FrameRelay.cleanup." + UUID().uuidString), generation: .init(rawValue: UUID()))
        let sdk = BackgroundSessionProbe(identity: session)
        let source = try ManagedUploadSource(run: services.run, originals: services.access)
        let background = ProductBackgroundMediaFactory(library: library, admission: BackgroundPermitProbe(),
            sessionFactory: { _ in sdk }, sourceFactory: { _ in source })
        return .init(parent: parent, library: library, services: services, originals: originals, background: background,
            sdk: sdk, source: source, registration: registration, identity: identity, session: session)
    }

    func add(_ name: String, evidence: Bool = true, terminal: Bool = true) async throws -> CleanupContractTarget {
        let binding = try await originals.original(name)
        let operation = MediaOperationID(rawValue: "cleanup-upload-" + name)
        let snapshot = try await mediaSnapshot(services.store)
        let request = MediaRequest(operation: operation, target: .original(binding.original), purpose: .upload,
            registration: registration, expectedStartRevision: snapshot.revision)
        _ = try await mediaCommit(services.store, .request(command: operation, value: request))
        let mac = UploadSessionID(rawValue: "cleanup-mac-" + name)
        let context = RemoteOperationContext(operation: operation, registration: registration, target: request.target, session: mac)
        _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: "cleanup-observation-" + name),
            operation: operation, target: request.target, registration: registration,
            value: .reconciled(.init(context: context, observation: .init(rawValue: 1), result: .notExecuted))))
        var wire = URLRequest(url: try #require(URL(string: "https://example.invalid/cleanup-fixture")))
        wire.httpMethod = "PUT"
        let plan = BackgroundMediaUploadPlan(id: .init(rawValue: "cleanup-task-" + name),
            context: .init(operation: operation, attempt: .init(rawValue: "cleanup-attempt-" + name), target: request.target,
                registration: registration, gateGeneration: 1, storeIdentity: identity), session: session,
            taskDescription: UUID().uuidString, sourceID: .init(rawValue: UUID().uuidString), macSession: mac, request: wire)
        guard case .started(let state) = await background.startUpload(plan), let task = state.binding else { throw BackendContractError.notCommitted }
        let result = CleanupContractTarget(binding: binding, plan: plan, task: task,
            invalidation: evidence ? try await cleanupContractEvidence(originals, binding: binding, context: context, schema: "fr-final-read-v1").1 : nil)
        if terminal { try await complete(result) }
        return result
    }

    func complete(_ target: CleanupContractTarget) async throws {
        await sdk.complete(target.task, outcome: .cancelled, finishEvents: true)
        // Let the single callback consumer commit true own-FD closure, exact
        // original-lease release, and stopped before using this as a fixture.
        try await backgroundEventually {
            (try? await mediaSnapshot(services.store).requests.first(where: {
                $0.operation == target.plan.context.operation
            })?.transport) == .stopped
        }
    }

    func composition() -> ProductComposition {
        ProductComposition(factory: library, backgroundFactory: background,
            registrationFactory: { RegistrationCoordinator(store: $0, vault: CleanupEmptyVault(), remote: RegistrationTestRemote()) })
    }

    func close() async throws { await sdk.finishStream(); _ = try await source.closeOwner() }
}

nonisolated private struct CleanupEmptyVault: RegistrationVaultPort {
    func connection(storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationConnection? { nil }
    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) async throws {
        throw RegistrationAccessError.credentialUnavailable
    }
    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationIntent {
        throw RegistrationAccessError.credentialUnavailable
    }
    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) async throws {
        throw RegistrationAccessError.credentialUnavailable
    }
}

nonisolated struct CleanupContractTarget: Sendable {
    let binding: OriginalBinding
    let plan: BackgroundMediaUploadPlan
    let task: BackgroundMediaTaskBinding
    let invalidation: InvalidationRecord?
}

nonisolated func cleanupContractEvidence(_ fixture: OriginalRemovalFixture, binding: OriginalBinding,
    context: RemoteOperationContext, schema: String) async throws -> (CleanupEvidenceSelection, InvalidationRecord) {
    let suffix = binding.original.capture.rawValue
    let rendition = RenditionIdentity(original: binding.original, inputLogIdentity: "synthetic-contract-log",
        transformAssetIdentity: "synthetic-contract-transform", transformAssetVersion: "fixture-v1",
        outputConfigurationIdentity: "synthetic-contract-output", conversionVersion: "fixture-v1",
        rendition: .init(rawValue: "cleanup-rendition-" + suffix), deliveryContent: binding.original.content,
        publicationGeneration: .init(rawValue: 1))
    _ = try await mediaCommit(fixture.store, .publication(mediaPublication(rendition, registration: context.registration)))
    let distributionOperation = MediaOperationID(rawValue: "cleanup-distribution-" + suffix)
    let distribution = DistributionReceipt(operation: distributionOperation, rendition: rendition, registration: context.registration,
        commit: backendCommit(.distribution(distributionOperation, rendition, context.registration), revision: 20))
    let confirmation = ConfirmationIntent(operation: .init(rawValue: "cleanup-confirmation-" + suffix),
        playback: try .init(distribution: distribution, session: .init(rawValue: "cleanup-play-" + suffix),
            invalidationGeneration: .init(rawValue: 0), observation: .played))
    _ = try await mediaCommit(fixture.store, .confirmation(confirmation))
    let command = MediaOperationID(rawValue: "cleanup-verification-" + suffix)
    let proof = VerificationEvidence(id: .init(rawValue: "cleanup-proof-" + suffix), context: context, finalSaveCompleted: true,
        verification: .finalDestinationReadBack(binding.original.content), committed: true, schemaVersion: schema,
        observedAt: Date(timeIntervalSince1970: 1))
    _ = try await mediaCommit(fixture.store, .verification(command: command, expected: context, evidence: proof))
    return (.init(registration: context.registration, verificationCommand: command, confirmationOperation: confirmation.operation),
        .init(id: .init(rawValue: "cleanup-invalidation-" + suffix), rendition: rendition, registration: context.registration, generation: .init(rawValue: 1)))
}
