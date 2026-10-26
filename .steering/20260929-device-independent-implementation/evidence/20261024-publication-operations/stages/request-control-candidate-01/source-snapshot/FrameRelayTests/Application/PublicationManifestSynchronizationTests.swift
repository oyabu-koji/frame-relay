import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct PublicationManifestSynchronizationTests {
    @Test func catalogOriginalsUseByteExactFixedIdentitiesAndNilObservationsDoNotCreateBindings() async throws {
        try await withStorageRun { run in
            let names = ["\u{e9}", "e\u{301}", String(repeating: "x", count: 2048)]
            let f = try await ManifestSynchronizationFixture.make(run: run, names: names)
            _ = try await inventoryCommit(f.store, inventoryObservation(f.identity, f.registration,
                originals: [f.originals[0]]))
            let report = await f.coordinator(run: run).synchronize()
            #expect(report.phase == .checked && report.items.count == 3)
            #expect(report.items.allSatisfy { $0.disposition == .noPublishedRecord })
            #expect(f.remote.manifestCalls.count == 3)
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.publicationManifests.count == 3 && snapshot.publications.isEmpty)
            #expect(snapshot.confirmations.isEmpty && snapshot.invalidations.isEmpty && snapshot.outbox.isEmpty)
            #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals.isEmpty)
            guard case .loaded(let library) = await LibraryStoreReader(store: f.store,
                files: StatusSynchronizationAbsentFiles()).loadLibrary() else { throw BackendContractError.unavailable }
            #expect(library.items.isEmpty && library.history.isEmpty && library.remoteItems.count == 3)
            #expect(library.remoteItems.allSatisfy { $0.publicationDescription.contains("最後の照合では公開版なし") })
            #expect(f.remote.mediaCalls == 0 && f.remote.sent.isEmpty)
        }
    }

    @Test func nilV1PendingSamePointerAndV2RemainMetadataWithoutManufacturingConfirmation() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            let coordinator = f.coordinator(run: run)
            #expect(await coordinator.synchronize().phase == .checked)
            let v1 = statusRendition(f.originals[0])
            f.remote.setManifest(v1, revision: 1)
            #expect(await coordinator.synchronize().phase == .checked)
            f.set(.init(current: v1, revision: 1, invalidationGeneration: .init(rawValue: 0),
                replacementPending: true, mediaType: "video/quicktime"))
            #expect(await coordinator.synchronize().items.first?.disposition == .unchanged)
            // A newer invalidation observation at the same pointer cannot alter
            // the confirmation authority without its separate durable event.
            f.set(.init(current: v1, revision: 1, invalidationGeneration: .init(rawValue: 1),
                replacementPending: true, mediaType: "video/quicktime"))
            #expect(await coordinator.synchronize().phase == .partial)
            let during = try await mediaSnapshot(f.store)
            #expect(during.publicationManifests.count == 4)
            #expect(during.publications.count == 1 && during.confirmationStates.first?.generation.rawValue == 0)
            let v2 = statusRendition(f.originals[0], version: 2)
            f.set(.init(current: v2, revision: 2, invalidationGeneration: .init(rawValue: 1),
                replacementPending: false, mediaType: "video/mp4"))
            #expect(await coordinator.synchronize().phase == .checked)
            let after = try await mediaSnapshot(f.store)
            #expect(after.publicationManifests.count == 5 && after.publications.count == 2)
            #expect(after.publicationManifests.last?.observation.manifest.current == v2)
            #expect(after.confirmations.isEmpty && after.invalidations.isEmpty && after.outbox.isEmpty)
            #expect(f.remote.mediaCalls == 0 && f.remote.sent.isEmpty)
        }
    }

    @Test func staleAndSameRevisionConflictingResponsesPreserveTheLastDurableObservation() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            let v1 = statusRendition(f.originals[0]), v2 = statusRendition(f.originals[0], version: 2)
            let coordinator = f.coordinator(run: run)
            f.remote.setManifest(v1, revision: 3)
            #expect(await coordinator.synchronize().phase == .checked)
            let before = try await mediaSnapshot(f.store)
            f.remote.setManifest(v2, revision: 3)
            #expect(await coordinator.synchronize().phase == .partial)
            f.remote.setManifest(v1, revision: 2)
            #expect(await coordinator.synchronize().phase == .partial)
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(f.remote.mediaCalls == 0 && f.remote.sent.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func uncertainManifestCommitRetainsOriginalMutationAndDoesNotFetchNewerMetadata(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            let fault = ManifestMetadataFaultStore(base: f.store)
            fault.afterCommit = afterCommit
            let coordinator = BackendStatusSynchronizationCoordinator(store: fault, identity: f.identity,
                registration: f.registration, remote: f.remote,
                invalidations: statusInvalidator(store: f.store, identity: f.identity, run: run))
            #expect(await coordinator.synchronize().phase == .partial)
            let original = try #require(fault.mutations.first)
            f.remote.setManifest(statusRendition(f.originals[0]), revision: 10)
            #expect(await coordinator.synchronize().phase == .partial)
            #expect(fault.mutations.count == 1 && fault.lookups.last == original)
            #expect(f.remote.manifestCalls.count == 1)
            if afterCommit {
                fault.hideLookup = false
                #expect(await coordinator.synchronize().items.first?.disposition == .recorded)
                #expect(fault.mutations.count == 1 && f.remote.manifestCalls.count == 1)
            } else {
                #expect(try await mediaSnapshot(f.store).publicationManifests.isEmpty)
            }
            #expect(f.remote.mediaCalls == 0 && f.remote.sent.isEmpty)
        }
    }

    @Test func recoveredPublicationAuthorityIsPartialUntilManifestMetadataIsAlsoPersisted() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            f.remote.setManifest(statusRendition(f.renditions[0].original, version: 2), revision: 2)
            f.store.losePublication = true; f.store.afterCommit = true; f.store.hideLookup = true
            let coordinator = f.coordinator()
            #expect(await coordinator.synchronize().phase == .partial)
            let mutation = try #require(f.store.mutations.first)
            f.store.hideLookup = false
            let reconciled = await coordinator.synchronize()
            #expect(reconciled.phase == .partial && reconciled.items.first?.disposition == .recorded)
            #expect(f.store.mutations == [mutation] && f.remote.manifestCalls.count == 1)
            #expect(try await mediaSnapshot(f.store).publicationManifests.isEmpty)
            f.store.losePublication = false
            #expect(await coordinator.synchronize().phase == .checked)
            #expect(try await mediaSnapshot(f.store).publicationManifests.count == 1)
            #expect(f.store.mutations == [mutation] && f.remote.manifestCalls.count == 2)
        }
    }

    @Test func changedStoreIdentityAfterRemoteAwaitCannotCommitTheOldObservation() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            let wrapper = ManifestMetadataFaultStore(base: f.store)
            f.remote.onManifest = { _ in wrapper.overrideIdentity = .init(rawValue: UUID()) }
            let coordinator = BackendStatusSynchronizationCoordinator(store: wrapper, identity: f.identity,
                registration: f.registration, remote: f.remote,
                invalidations: statusInvalidator(store: f.store, identity: f.identity, run: run))
            #expect(await coordinator.synchronize().phase == .unavailable)
            #expect(wrapper.mutations.isEmpty && f.remote.mediaCalls == 0)
            #expect(try await mediaSnapshot(f.store).publicationManifests.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func nonNilUnicodeAliasesRetainMetadataButCannotShareAuthorityOrInvalidateTheOtherOwner(reversed: Bool) async throws {
        try await withStorageRun { run in
            let names = reversed ? ["e\u{301}", "\u{e9}"] : ["\u{e9}", "e\u{301}"]
            let f = try await ManifestSynchronizationFixture.make(run: run, names: names)
            let first = statusRendition(f.originals[0]), second = statusRendition(f.originals[1], version: 2)
            f.remote.setManifest(first, revision: 1)
            f.remote.setManifest(second, revision: 2)
            let external = PublicationExternalFixture()
            let coordinator = f.coordinator(run: run, external: external)
            let report = await coordinator.synchronize()
            #expect(report.phase == .partial && report.items.map(\.disposition) == [.recorded, .unresolved])
            let before = try await mediaSnapshot(f.store)
            let originals = try await mediaOriginalSnapshot(f.store)
            #expect(before.publications.count == 1 && before.publicationManifests.count == 2)
            #expect(originals.logicalOriginals.count == 1)
            let logical = try #require(originals.logicalOriginals.first)
            #expect(PublicationStoreBoundary.exact(logical.original, first.original))
            #expect(PublicationStoreBoundary.exact(before.confirmationStates.first?.current, first))
            #expect(PublicationStoreBoundary.exact(before.publicationManifests[0].observation.original, first.original))
            #expect(PublicationStoreBoundary.exact(before.publicationManifests[1].observation.original, second.original))
            #expect(before.publicationManifests[1].observation.manifest.current == second)

            let invalidation = statusInvalidation(second, registration: f.registration.server.registration,
                id: "non-adopted-alias-invalidation")
            f.remote.pages = [.succeeded(.init(records: [invalidation], nextAfter: nil))]
            let retried = await coordinator.synchronize()
            #expect(retried.phase == .partial && retried.unresolvedInvalidations == 1)
            let after = try await mediaSnapshot(f.store)
            let afterOriginals = try await mediaOriginalSnapshot(f.store)
            #expect(after == before && afterOriginals.logicalOriginals == originals.logicalOriginals)
            #expect(afterOriginals.logicalOriginals.first?.invalidation == nil)
            #expect(after.invalidations.isEmpty && after.outbox.isEmpty && after.confirmations.isEmpty)
            #expect(external.stops == 0 && f.remote.sent.isEmpty && f.remote.mediaCalls == 0)
        }
    }

    @Test(arguments: [false, true])
    func legacyMergedAliasAuthorityRemainsReadableButNeverHandsOffTheWrongLogicalOwner(reversed: Bool) async throws {
        try await withStorageRun { run in
            let names = reversed ? ["e\u{301}", "\u{e9}"] : ["\u{e9}", "e\u{301}"]
            let f = try await ManifestSynchronizationFixture.make(run: run, names: names)
            let first = statusRendition(f.originals[0]), second = statusRendition(f.originals[1], version: 2)
            // Reproduce historical writer acceptance without changing its
            // schema/replay semantics. This is not a new product admission.
            _ = try await mediaCommit(f.store, .publication(mediaPublication(first,
                registration: f.registration.server.registration, observation: 1)))
            _ = try await mediaCommit(f.store, .publication(mediaPublication(second,
                registration: f.registration.server.registration, observation: 2)))
            let before = try await mediaSnapshot(f.store)
            let beforeOriginals = try await mediaOriginalSnapshot(f.store)
            #expect(beforeOriginals.logicalOriginals.count == 1)
            #expect(PublicationStoreBoundary.exact(beforeOriginals.logicalOriginals.first?.original, first.original))
            #expect(PublicationStoreBoundary.exact(before.confirmationStates.first?.current, second))
            let invalidation = statusInvalidation(second, registration: f.registration.server.registration,
                id: "historical-merged-alias-invalidation")
            f.remote.pages = [.succeeded(.init(records: [invalidation], nextAfter: nil))]
            f.remote.setManifest(first, revision: 1)
            f.remote.setManifest(second, revision: 2)
            let external = PublicationExternalFixture()
            let report = await f.coordinator(run: run, external: external).synchronize()
            #expect(report.phase == .partial && report.unresolvedInvalidations == 1)
            let after = try await mediaSnapshot(f.store)
            let afterOriginals = try await mediaOriginalSnapshot(f.store)
            #expect(after.publications == before.publications && after.publicationManifests.count == 2)
            #expect(afterOriginals.logicalOriginals == beforeOriginals.logicalOriginals)
            #expect(PublicationStoreBoundary.exact(after.confirmationStates.first?.current, second))
            #expect(after.confirmationStates.first?.generation == before.confirmationStates.first?.generation)
            #expect(after.invalidations.isEmpty && after.outbox.isEmpty && after.confirmations.isEmpty)
            #expect(external.stops == 0 && f.remote.sent.isEmpty && f.remote.mediaCalls == 0)
            let reopened = try statusSynchronizationDisk(.sqlite, run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened) == after)
        }
    }

    @Test func registrationChangeDuringManifestAwaitCannotCommitOldMetadata() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            f.remote.onManifest = { _ in
                _ = try? await mediaRegister(f.store, registration: .init(
                    destination: f.registration.server.registration.destination,
                    id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
            }
            #expect(await f.coordinator(run: run).synchronize().phase == .unavailable)
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.publicationManifests.isEmpty && snapshot.publications.isEmpty)
            #expect(snapshot.confirmations.isEmpty && snapshot.outbox.isEmpty && f.remote.mediaCalls == 0)
        }
    }
}

/// All metadata is synthetic input; disk and Library projection are real. The
/// fixture does not create media, Keychain entries, Photos or formal proof.
@MainActor struct ManifestSynchronizationFixture {
    let store: any MediaDiskStore
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let originals: [OriginalContent]
    let remote: StatusMetadataRemote

    static func make(run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite,
        names: [String] = ["manifest-catalog"]) async throws -> Self {
        let store = try statusSynchronizationDisk(candidate, run: run, mode: .createNew)
        let registration = try await inventoryRegister(store)
        let identity = try #require(try await mediaSnapshot(store).storeIdentity)
        let originals = try names.map { try inventoryOriginal($0) }
        _ = try await inventoryCommit(store, inventoryObservation(identity, registration, originals: originals))
        let remote = StatusMetadataRemote()
        remote.manifests = originals.map { ($0, .succeeded(.init(current: nil, revision: 0,
            invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: nil))) }
        return .init(store: store, identity: identity, registration: registration, originals: originals, remote: remote)
    }
    func coordinator(run: ExplorationRunDirectory) -> BackendStatusSynchronizationCoordinator {
        .init(store: store, identity: identity, registration: registration, remote: remote,
            invalidations: statusInvalidator(store: store, identity: identity, run: run))
    }
    func coordinator(run: ExplorationRunDirectory, external: any PublicationExternalTerminationPort) -> BackendStatusSynchronizationCoordinator {
        let invalidations = MediaInvalidationCoordinator(store: store, identity: identity,
            ordering: ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run)),
            scopes: RenditionScopeRegistry(leases: RenditionReadLeases(store: store)), external: external)
        return .init(store: store, identity: identity, registration: registration, remote: remote,
            invalidations: invalidations)
    }
    func set(_ manifest: PublicationManifest, index: Int = 0) { remote.manifests[index].1 = .succeeded(manifest) }
    func observation(_ manifest: PublicationManifest, index: Int = 0,
        command: MediaOperationID = .init(rawValue: UUID().uuidString)) -> PublicationManifestObservation {
        .init(command: command, storeIdentity: identity, registration: registration.server.registration,
            original: originals[index], manifest: manifest)
    }
    func commit(_ value: PublicationManifestObservation) async throws -> BackendCommitReceipt {
        let before = try await mediaSnapshot(store)
        guard case .committed(let receipt) = await store.commit(.init(expectedRevision: before.revision,
            change: .publicationManifest(value), expectedStoreIdentity: identity)) else { throw BackendContractError.notCommitted }
        return receipt
    }
}

@MainActor final class ManifestMetadataFaultStore {
    let base: any MediaDiskStore
    var afterCommit = false
    var hideLookup = true
    var overrideIdentity: RegistrationStoreIdentity?
    private(set) var mutations: [BackendStoreMutation] = []
    private(set) var lookups: [BackendStoreMutation] = []
    init(base: any MediaDiskStore) { self.base = base }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .publicationManifest = mutation.change {
            mutations.append(mutation)
            if afterCommit { _ = await base.commit(mutation) }
            return .unknown
        }
        return await base.commit(mutation)
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        lookups.append(mutation)
        return hideLookup ? .unknown : await base.lookupCommit(mutation)
    }
    func load() async -> BackendStoreLoadResult {
        let result = await base.load()
        guard let overrideIdentity, case .loaded(var value) = result else { return result }
        value.storeIdentity = overrideIdentity
        return .loaded(value)
    }
    func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        await base.lookupInvalidation(acknowledgement)
    }
}
extension ManifestMetadataFaultStore: MediaOperationStorePort, OriginalStorePort {}
