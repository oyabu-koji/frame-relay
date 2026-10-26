import Foundation
import Testing
@testable import FrameRelay

@MainActor struct ProductRemovalCompositionTests {
    @Test func ordinaryCompositionDiscardsOneUntransferredOriginalAndProjectsItsExactResult() async throws {
        let parent = try removalCompositionParent()
        let factory = ProductLibraryFactory(supportDirectory: parent)
        let services = try await factory.open()
        let fixture = OriginalRemovalFixture(run: services.run, store: services.store, files: services.originals, access: services.access)
        let binding = try await fixture.original("s34-normal-discard", unknown: true)
        let keep = try await fixture.original("s34-normal-keep", unknown: true)
        let composition = removalComposition(factory)
        await composition.open()
        let model = try #require(composition.library)
        #expect(model.availability(.discard, captures: [binding.original.capture]) == .available)
        #expect(model.availability(.cleanup, captures: [binding.original.capture]).reason?.contains("通信の終了") == true)
        let review = try #require(model.prepareRemovalReview(.discard, captures: [binding.original.capture]))
        model.select(keep.original.capture, selected: true)
        await model.submit(review)
        #expect(model.submission?.request.targets.map(\.capture) == [binding.original.capture])
        #expect(model.submission?.phase == .awaitingRecordedResult)
        #expect(model.item(binding.original.capture)?.isDiscardHistory == true)
        #expect(model.item(binding.original.capture)?.operationResults.first?.id == review.id)
        #expect(model.item(binding.original.capture)?.operationResults.first?.outcome == .succeeded)
        #expect(await services.originals.observeFile(binding.reference) == .absent)
        #expect(await services.originals.observeFile(keep.reference) == .present(byteCount: keep.original.content.byteCount))
        #expect(model.item(binding.original.capture)?.recording.result == binding.saveRecord)
        let reopened = try await ProductLibraryFactory(supportDirectory: parent).open()
        guard case .loaded(let snapshot) = await reopened.reader.loadLibrary() else { throw BackendContractError.unavailable }
        #expect(snapshot.history.map(\.id) == [binding.original.capture])
        #expect(snapshot.items.first(where: { $0.id == binding.original.capture })?.operationResults.first?.outcome == .succeeded)
        let media = try #require(composition.mediaTermination)
        let scopes = await media.scopes
        let next = try await scopes.open(original: binding.original)
        _ = try await next.close()
    }

    @Test(arguments: [false, true])
    func dialogKeepsExactBindingAndSelection(changeBinding: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let a = try await fixture.original("review-a", unknown: true)
            let b = try await fixture.original("review-b", unknown: true)
            let diskReader = LibraryStoreReader(store: fixture.store, files: fixture.files)
            guard case .loaded(let snapshot) = await diskReader.loadLibrary() else { throw BackendContractError.unavailable }
            let reader = RemovalReviewReader(snapshot)
            let commands = RemovalReviewCommands()
            let model = LibraryModel(reader: reader, commands: commands)
            await model.refresh()
            let review = try #require(model.prepareRemovalReview(.discard, captures: [a.original.capture]))
            model.select(b.original.capture, selected: true)
            if changeBinding {
                let old = try #require(snapshot.items.first(where: { $0.id == a.original.capture }))
                let replacement = LibraryItem(recording: old.recording, file: old.file,
                    original: .init(capture: a.original.capture, generation: .init(rawValue: 99), content: a.original.content),
                    removal: old.removal, requiresReconciliation: old.requiresReconciliation, statuses: old.statuses)
                reader.snapshot = .init(revision: snapshot.revision + 1,
                    items: snapshot.items.map { $0.id == a.original.capture ? replacement : $0 })
                await model.refresh()
            }
            await model.submit(review)
            if changeBinding {
                #expect(commands.requests.isEmpty)
                #expect(model.inputIssue?.contains("対象が更新") == true)
            } else {
                #expect(commands.requests.count == 1)
                #expect(commands.requests.first?.targets == review.targets)
                #expect(commands.requests.first?.discardRiskAcknowledged == true)
            }
            #expect(await fixture.files.observeFile(a.reference) == .present(byteCount: a.original.content.byteCount))
            #expect(await fixture.files.observeFile(b.reference) == .present(byteCount: b.original.content.byteCount))
        }
    }

    @Test(arguments: [1, 2, 3])
    func captureAdmissionIsCheckedBeforeStopAfterStopAndBeforeExecution(denyAt: Int) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("capture-admission", unknown: true)
            let adapter = AVOriginalPlayback(access: fixture.access)
            let registry = RenditionScopeRegistry(leases: RenditionReadLeases(store: fixture.store))
            let gate = RemovalAdmissionGate(denyAt: denyAt)
            let termination = ProductRemovalTermination(store: fixture.store, access: fixture.access, player: adapter,
                scopes: registry, admission: { gate.permit() })
            let execution = ProductRemovalExecution(access: fixture.access, admission: { gate.permit() })
            let coordinator = DiscardCoordinator(store: fixture.store, termination: termination, execution: execution)
            let batch = try fixture.discardBatch(binding)
            guard case .succeeded(let result) = await coordinator.start(batch) else { throw BackendContractError.notCommitted }
            #expect(result.targets.first?.status == .notExecuted(denyAt == 3 ? .ineligible : .terminationUnconfirmed))
            #expect(await fixture.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.removal == nil)
            #expect(await termination.finish(result))
            let opened = try await registry.open(original: binding.original)
            _ = try await opened.close()
            try await removalAssertPlayerAdmits(adapter, original: binding.original)
        }
    }

    @Test(arguments: [false, true])
    func removalAndInvalidationReleaseOnlyTheirOwnSealAndReobserveCurrentAccess(invalidationFirst: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("seal-interleaving", unknown: true)
            let invalidation = try await removalPublication(fixture, binding: binding)
            let adapter = AVOriginalPlayback(access: fixture.access)
            let media = ProductMediaTermination(store: fixture.store, access: fixture.access, player: adapter)
            let scopes = await media.scopes
            let termination = ProductRemovalTermination(store: fixture.store, access: fixture.access, player: adapter,
                scopes: scopes, admission: { true })
            let earlierScope = try await media.scopes.open(original: binding.original)
            let earlierTerminal = try await earlierScope.close()
            let batch = try fixture.discardBatch(binding)
            let before = try await mediaOriginalSnapshot(fixture.store)
            guard case .committed = await fixture.store.commitOriginal(.init(operation: batch.operation,
                expectedRevision: before.revision, change: .removalBatch(batch))),
                  case .succeeded(let old) = await termination.stopForRemoval(batch.targets[0]) else {
                throw BackendContractError.notCommitted
            }
            // An explicitly owned descriptor opens/closes outside those factory
            // inventories. The release must reobserve today's access generation.
            guard case .succeeded(let source) = await fixture.access.acquirePlayback(binding.original,
                operation: .init(rawValue: "intervening-owner"), leaseID: .init(rawValue: "intervening-reader")) else {
                throw BackendContractError.readersActive
            }
            #expect(await fixture.access.releaseRead(source.lease) == .succeeded(.init(lease: source.lease)))
            guard case .succeeded(let permit) = await fixture.access.reserveInvalidation(invalidation) else { throw BackendContractError.notCommitted }
            _ = try await media.scopes.stopAndReconcile(original: binding.original, external: media)
            _ = try await mediaOriginalCommit(fixture.store, .removalNotExecuted(batch: batch.operation,
                target: batch.targets[0], reason: .ineligible))
            let receipt = try await mediaCommit(fixture.store, .invalidation(invalidation, permit))
            let ack = InvalidationAcknowledgement(record: invalidation, commit: receipt)
            let record = try #require(try await mediaOriginalSnapshot(fixture.store).removalBatches.first)
            if invalidationFirst { try await media.resume(after: ack) }
            else { #expect(await termination.finish(record)) }
            do {
                _ = try await media.scopes.open(original: binding.original)
                Issue.record("The other owner's seal must remain closed")
            } catch { }
            #expect(await adapter.open(binding.original, operation: .init(rawValue: "still-sealed"),
                session: .init(rawValue: "still-sealed")) == .notExecuted)
            if invalidationFirst { #expect(await termination.finish(record)) }
            else { try await media.resume(after: ack) }
            let current = try await mediaOriginalSnapshot(fixture.store)
            #expect(current.logicalOriginals.first?.accessGeneration != old.readers.accessGeneration)
            #expect(try await earlierScope.close() == earlierTerminal)
            let next = try await media.scopes.open(original: binding.original)
            _ = try await next.close()
            try await removalAssertPlayerAdmits(adapter, original: binding.original)
            #expect(await fixture.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
        }
    }

    @Test func removalReleaseRequiresItsExactOwnerAndFreshCommonObservation() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("fresh-seal", unknown: true)
            let registry = RenditionScopeRegistry(leases: RenditionReadLeases(store: fixture.store))
            let player = AVOriginalPlayback(access: fixture.access)
            let external = PublicationExternalFixture()
            let scope = try await registry.open(original: binding.original)
            let terminal = try await scope.close()
            let batch = try fixture.discardBatch(binding)
            let before = try await mediaOriginalSnapshot(fixture.store)
            guard case .committed = await fixture.store.commitOriginal(.init(operation: batch.operation,
                expectedRevision: before.revision, change: .removalBatch(batch))) else { throw BackendContractError.notCommitted }
            let seal = OriginalRemovalAdmissionSeal(batch: batch.operation, target: batch.targets[0], nonce: "owner-nonce")
            _ = try await registry.stopForRemoval(seal, external: external)
            _ = try await player.stopForRemoval(seal)
            _ = try await mediaOriginalCommit(fixture.store, .removalNotExecuted(batch: batch.operation,
                target: batch.targets[0], reason: .ineligible))
            let snapshot = try await mediaOriginalSnapshot(fixture.store)
            let epoch = try #require(snapshot.reconciliationEpoch)
            let state = try #require(snapshot.logicalOriginals.first)
            let wrongChild = OriginalRemovalTarget(original: binding.original, reference: binding.reference,
                operation: .init(rawValue: "other-child"))
            let invalid = [
                OriginalRemovalAdmissionRelease(seal: .init(batch: batch.operation, target: seal.target, nonce: "other-nonce"),
                    epoch: epoch, access: state.accessGeneration, invalidation: state.invalidationGeneration, resolution: nil),
                .init(seal: .init(batch: batch.operation, target: wrongChild, nonce: seal.nonce),
                    epoch: epoch, access: state.accessGeneration, invalidation: state.invalidationGeneration, resolution: nil),
                .init(seal: seal, epoch: .init(rawValue: "earlier-process"), access: state.accessGeneration,
                    invalidation: state.invalidationGeneration, resolution: nil)
            ]
            for release in invalid {
                do { try await registry.resumeAfterRemoval(release); Issue.record("A different owner/epoch cannot release the registry") } catch { }
                // Common writer epoch is the producer/registry authority. The
                // SDK owner separately rejects another nonce or child.
                if release.epoch == epoch {
                    do { try await player.resumeAfterRemoval(release); Issue.record("A different owner cannot release the player") } catch { }
                }
            }
            guard case .succeeded(let source) = await fixture.access.acquirePlayback(binding.original,
                operation: .init(rawValue: "new-access"), leaseID: .init(rawValue: "new-access-reader")),
                  case .succeeded = await fixture.access.releaseRead(source.lease) else { throw BackendContractError.readersActive }
            // Even a current writer reconciliation from elsewhere cannot turn
            // this owner's old inventory into a fresh stop observation.
            try await mediaReconcile(fixture.store, original: binding.original)
            let current = try #require(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first)
            let release = OriginalRemovalAdmissionRelease(seal: seal, epoch: epoch, access: current.accessGeneration,
                invalidation: current.invalidationGeneration, resolution: nil)
            #expect(current.accessGeneration != terminal.accessGeneration)
            do { try await registry.resumeAfterRemoval(release); Issue.record("Fresh stop/reconcile is mandatory") } catch { }
            _ = try await registry.stopForRemoval(seal, external: external)
            try await registry.resumeAfterRemoval(release)
            try await player.resumeAfterRemoval(release)
            #expect(try await scope.close() == terminal)
            let next = try await registry.open(original: binding.original)
            _ = try await next.close()
            try await removalAssertPlayerAdmits(player, original: binding.original)
        }
    }

    @Test(arguments: [OriginalRemovalFaultStore.Stage.batch, .reserve])
    func explicitCheckClosesOnlyItsUnprocessedChildAndNeverRetriesUnlink(stage: OriginalRemovalFaultStore.Stage) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let a = try await fixture.original("check-a", unknown: true)
            let b = try await fixture.original("check-b", unknown: true)
            let batchA = try fixture.discardBatch(a, name: "uncertain-a")
            let batchB = try fixture.discardBatch(b, name: "untouched-b")
            let before = try await mediaOriginalSnapshot(fixture.store)
            guard case .committed = await fixture.store.commitOriginal(.init(operation: batchB.operation,
                expectedRevision: before.revision, change: .removalBatch(batchB))) else { throw BackendContractError.notCommitted }
            let fault = OriginalRemovalFaultStore(base: fixture.store)
            fault.configure(stage, afterCommit: stage == .batch)
            let access = ManagedOriginalAccess(store: fault, originals: fixture.files)
            let adapter = AVOriginalPlayback(access: access)
            let registry = RenditionScopeRegistry(leases: RenditionReadLeases(store: fault))
            let termination = ProductRemovalTermination(store: fault, access: access, player: adapter,
                scopes: registry, admission: { true })
            let execution = ProductRemovalExecution(access: access, admission: { true })
            let coordinator = DiscardCoordinator(store: fault, termination: termination, execution: execution)
            #expect(await coordinator.start(batchA) == .unknown)
            #expect(try await mediaOriginalSnapshot(fixture.store).removalBatches.first(where: { $0.batch == batchA })?
                .targets.first?.status == .unprocessed)
            fault.configure(nil)
            let reader = LibraryStoreReader(store: fault, files: fixture.files)
            let beforeRead = try await mediaOriginalSnapshot(fixture.store)
            _ = await reader.loadLibrary()
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: .sqlite)
            _ = await LibraryStoreReader(store: reopened, files: ManagedOriginalStore(run: run)).loadLibrary()
            #expect(try await mediaOriginalSnapshot(fixture.store) == beforeRead)
            let bridge = LibraryRemovalCommands(base: UnconnectedLibraryCommands(), reader: reader, store: fault,
                discard: coordinator,
                execution: execution, termination: termination, admission: { true })
            guard case .loaded(let library) = await reader.loadLibrary(),
                  let operation = library.items.first(where: { $0.id == a.original.capture })?.removalOperations.first else {
                throw BackendContractError.unavailable
            }
            guard case .succeeded(let closed) = await bridge.reconcile(operation) else { throw BackendContractError.notCommitted }
            #expect(closed.targets.first?.status == .notExecuted(.unavailable))
            let current = try await mediaOriginalSnapshot(fixture.store)
            #expect(current.removalBatches.first(where: { $0.batch == batchB })?.targets.first?.status == .unprocessed)
            #expect(await fixture.files.observeFile(a.reference) == .present(byteCount: a.original.content.byteCount))
            #expect(await fixture.files.observeFile(b.reference) == .present(byteCount: b.original.content.byteCount))
            guard case .succeeded(let released) = await access.reconcileReaders(a.original) else { throw BackendContractError.readersActive }
            #expect(await access.removeOriginal(batch: batchA, target: batchA.targets[0], evidence: nil,
                quiescence: .init(target: batchA.targets[0], transport: .neverStarted(.original(a.original)), readers: released)) == .notExecuted)
            try await removalAssertPlayerAdmits(adapter, original: a.original)
        }
    }

    @Test func explicitCheckClosesUnprocessedChildWhileItsReservationIsInFlight() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("check-during-start", unknown: true)
            let batch = try fixture.discardBatch(binding)
            let fault = OriginalRemovalFaultStore(base: fixture.store)
            let barrier = OriginalRemovalDigestBarrier()
            fault.reservationBarrier = barrier
            let access = ManagedOriginalAccess(store: fault, originals: fixture.files)
            let adapter = AVOriginalPlayback(access: access)
            let registry = RenditionScopeRegistry(leases: RenditionReadLeases(store: fault))
            let termination = ProductRemovalTermination(store: fault, access: access, player: adapter,
                scopes: registry, admission: { true })
            let execution = ProductRemovalExecution(access: access, admission: { true })
            let coordinator = DiscardCoordinator(store: fault, termination: termination, execution: execution)
            let reader = LibraryStoreReader(store: fault, files: fixture.files)
            let bridge = LibraryRemovalCommands(base: UnconnectedLibraryCommands(), reader: reader, store: fault,
                discard: coordinator, execution: execution, termination: termination, admission: { true })
            let start = Task { await coordinator.start(batch) }
            do { try await barrier.wait() }
            catch { await barrier.resume(); _ = await start.value; throw error }
            guard case .loaded(let snapshot) = await reader.loadLibrary(),
                  let operation = snapshot.items.first?.removalOperations.first else {
                await barrier.resume(); _ = await start.value; throw BackendContractError.unavailable
            }
            let checked = await bridge.reconcile(operation)
            await barrier.resume()
            let finished = await start.value
            guard case .succeeded(let record) = checked else { throw BackendContractError.notCommitted }
            #expect(record.targets.first?.status == .notExecuted(.unavailable))
            #expect(finished == .unknown)
            let final = try await mediaOriginalSnapshot(fixture.store)
            #expect(final.removalBatches.first?.targets.first?.status == .notExecuted(.unavailable))
            #expect(final.originals.first?.removal == nil && final.originals.first?.resolvedRemoval == nil)
            #expect(await fixture.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            try await removalAssertPlayerAdmits(adapter, original: binding.original)
        }
    }
}

@MainActor private func removalAssertPlayerAdmits(_ player: AVOriginalPlayback, original: OriginalContent) async throws {
    let id = PlaybackSessionID(rawValue: UUID().uuidString)
    let attempt = RemovalPlaybackAttempt()
    let task = Task {
        let result = await player.open(original, operation: .init(rawValue: UUID().uuidString), session: id)
        attempt.result = result
        return result
    }
    _ = await renditionEventually(seconds: 10) {
        (player.activeSession == id && player.activeSource != nil && player.phase == .playing && player.deliveredBytes > 0)
            || (attempt.result != nil && player.activeSession == nil)
    }
    let admitted = player.activeSession == id && player.activeSource != nil && player.phase == .playing && player.deliveredBytes > 0
    let source = player.activeSource
    let before = "phase=\(player.phase) issue=\(player.issue ?? "none") bytes=\(player.deliveredBytes) release=\(player.lastRelease)"
    await player.stopOriginal(id)
    let outcome = await task.value
    print("S34_REMOVAL_PLAYBACK capture=\(original.capture.rawValue) beforeStop={\(before)} outcome=\(outcome) afterRelease=\(player.lastRelease)")
    #expect(admitted)
    let actual = try #require(source)
    #expect(player.lastRelease == .succeeded(.init(lease: actual.lease)))
}

@MainActor private final class RemovalPlaybackAttempt {
    var result: BackendOutcome<OriginalPlaybackProgress>?
}

@MainActor private func removalComposition(_ factory: ProductLibraryFactory) -> ProductComposition {
    .init(factory: factory, registrationFactory: { store in
        RegistrationCoordinator(store: store, vault: RemovalEmptyVault(), remote: RegistrationTestRemote())
    })
}
nonisolated private func removalCompositionParent() throws -> URL {
    let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FrameRelay-removal-composition-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
nonisolated private func removalPublication(_ fixture: OriginalRemovalFixture, binding: OriginalBinding) async throws -> InvalidationRecord {
    let registration = try await mediaRegister(fixture.store)
    let rendition = RenditionIdentity(original: binding.original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "synthetic-not-quality",
        transformAssetVersion: "fixture-v1", outputConfigurationIdentity: "fixture", conversionVersion: "fixture",
        rendition: .init(rawValue: "s34-fixture-rendition"), deliveryContent: binding.original.content, publicationGeneration: .init(rawValue: 1))
    _ = try await mediaCommit(fixture.store, .publication(mediaPublication(rendition, registration: registration)))
    return .init(id: .init(rawValue: "s34-invalidation"), rendition: rendition, registration: registration, generation: .init(rawValue: 1))
}
@MainActor private final class RemovalAdmissionGate {
    private var calls = 0
    let denyAt: Int
    init(denyAt: Int) { self.denyAt = denyAt }
    func permit() -> Bool { calls += 1; return calls != denyAt }
}
@MainActor private final class RemovalReviewReader: LibraryReadPort {
    var snapshot: LibrarySnapshot
    init(_ snapshot: LibrarySnapshot) { self.snapshot = snapshot }
    @MainActor func loadLibrary() async -> LibraryLoadResult { .loaded(snapshot) }
}
@MainActor private final class RemovalReviewCommands: LibraryCommandPort {
    private(set) var requests: [LibraryCommandRequest] = []
    func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability { .available }
    @MainActor func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse { requests.append(request); return .accepted }
}
nonisolated private struct RemovalEmptyVault: RegistrationVaultPort {
    func connection(storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationConnection? { nil }
    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) async throws { throw RegistrationAccessError.credentialUnavailable }
    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationIntent { throw RegistrationAccessError.credentialUnavailable }
    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) async throws { throw RegistrationAccessError.credentialUnavailable }
}
