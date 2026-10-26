import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct StatusSynchronizationStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func metadataCommitAndIndependentLibraryAxesSurviveActualDiskReopen(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let store = try statusSynchronizationDisk(candidate, run: run, mode: .createNew)
            let identity = try await establishRegistrationIdentity(store)
            let registration = try await mediaRegister(store)
            let registered = try #require(try await mediaSnapshot(store).registrations.last)
            let binding = try await statusKnownOriginal(try publicationOriginal("disk-status"), store: store)
            let rendition = statusRendition(binding.original)
            let remote = StatusMetadataRemote(); remote.setManifest(rendition, revision: 1)
            let invalidations = statusInvalidator(store: store, identity: identity, run: run)
            let coordinator = BackendStatusSynchronizationCoordinator(store: store, identity: identity, registration: registered,
                remote: remote, invalidations: invalidations)
            #expect(await coordinator.synchronize().phase == .checked)
            let reopened = try statusSynchronizationDisk(candidate, run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.publications.count == 1 && snapshot.publications[0].observation.rendition == rendition)
            #expect(snapshot.confirmations.isEmpty && snapshot.outbox.isEmpty)
            #expect(snapshot.registrations.last?.server.registration == registration)
            let files = StatusSynchronizationAbsentFiles()
            let reader = LibraryStoreReader(store: reopened, files: files)
            guard case .loaded(let library) = await reader.loadLibrary(), let item = library.items.first else {
                throw BackendContractError.unavailable
            }
            #expect(item.status(.publication).contains("公開版の保存記録あり"))
            #expect(item.status(.confirmation).contains("明示確認なし"))
            #expect(item.status(.retrieval).contains("オフライン再生不可"))
            #expect(item.status(.original) == "原本なし")
            #expect(!item.isDiscardHistory)
            #expect(try await mediaSnapshot(reopened) == snapshot)
            #expect(remote.mediaCalls == 0)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func realDiskFaultRetainsOnlyExactCommittedPublication(candidate: StorageCandidate, fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run, candidate: candidate)
            let failedDisk = try statusSynchronizationDisk(candidate, run: run, mode: .openExisting, fault: fault)
            let hidden = StatusSynchronizationFaultStore(base: failedDisk); hidden.hideLookup = true
            let rendition = statusRendition(f.renditions[0].original, version: 2)
            f.remote.setManifest(rendition, revision: 2)
            let coordinator = BackendStatusSynchronizationCoordinator(store: hidden, identity: f.identity, registration: f.registration,
                remote: f.remote, invalidations: statusInvalidator(store: hidden, identity: f.identity, run: run))
            #expect(await coordinator.synchronize().phase == .partial)
            let mutation = try #require(hidden.mutations.last)
            let reopened = try statusSynchronizationDisk(candidate, run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            if fault == .afterDiskCommitBeforeReply {
                let receipt = try #require(snapshot.publications.last?.commit)
                #expect(snapshot.publications.count == 2)
                #expect(await reopened.lookupCommit(mutation) == .committed(receipt))
                let changed = BackendStoreMutation(expectedRevision: mutation.expectedRevision + 1,
                    change: mutation.change, expectedStoreIdentity: f.identity)
                #expect(await reopened.lookupCommit(changed) == .rejected(.identityMismatch))
            } else {
                #expect(snapshot.publications.count == 1)
                #expect(await reopened.lookupCommit(mutation) == .unknown)
            }
            #expect(snapshot.confirmations.isEmpty && snapshot.invalidations.isEmpty && snapshot.outbox.isEmpty)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func reopenStartsAtNullAndCannotSubstituteNewRegistrationForOldReservation(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run, candidate: candidate)
            let record = statusInvalidation(f.renditions[0], registration: f.registration.server.registration)
            f.external.available = false
            f.remote.pages = [.succeeded(.init(records: [record], nextAfter: record.id))]
            #expect(await f.coordinator().synchronize().hasMore)
            let reopened = try statusSynchronizationDisk(candidate, run: run, mode: .openExisting)
            let nextIdentity = try await mediaRegister(reopened, registration: .init(destination: record.registration.destination,
                id: .init(rawValue: "new-registration"), generation: .init(rawValue: 2)))
            let next = try #require(try await mediaSnapshot(reopened).registrations.last)
            let remote = StatusMetadataRemote(); remote.setManifest(f.renditions[0], revision: 1)
            let coordinator = BackendStatusSynchronizationCoordinator(store: reopened, identity: f.identity, registration: next,
                remote: remote, invalidations: statusInvalidator(store: reopened, identity: f.identity, run: run))
            let result = await coordinator.synchronize()
            #expect(result.phase == .partial && result.unresolvedInvalidations == 1)
            #expect(remote.afters.count == 1 && remote.afters[0] == nil)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.invalidations.isEmpty && snapshot.confirmations.isEmpty)
            #expect(snapshot.confirmationStates.last?.registration == nextIdentity)
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.first?.invalidation?.record == record)
            #expect(remote.sent.isEmpty && remote.mediaCalls == 0)
        }
    }

    @Test func historicalOutboxRetainsItsOwnRegistrationAndNeverRestoresConfirmationToNewOne() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let confirmations = MediaConfirmationCoordinator(store: f.store, identity: f.identity)
            let token = try publicationToken(f.renditions[0], registration: f.registration.server.registration)
            guard case .succeeded(let old) = await confirmations.confirm(token, action: .init(rawValue: "old-explicit-action")) else {
                throw BackendContractError.notCommitted
            }
            _ = try await mediaRegister(f.store.base, registration: .init(destination: f.registration.server.registration.destination,
                id: .init(rawValue: "next-registration"), generation: .init(rawValue: 2)))
            let next = try #require(try await mediaSnapshot(f.store).registrations.last)
            let coordinator = BackendStatusSynchronizationCoordinator(store: f.store, identity: f.identity, registration: next,
                remote: f.remote, invalidations: statusInvalidator(store: f.store, identity: f.identity, run: run))
            _ = await coordinator.synchronize()
            #expect(f.remote.sent == [.confirmation(old)])
            #expect(f.remote.sent[0].registration == f.registration.server.registration)
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.confirmations == [old])
            #expect(snapshot.confirmationStates.last?.registration == next.server.registration)
            #expect(snapshot.confirmationStates.last?.validConfirmation == nil)
        }
    }

    @Test func canonicalEquivalentRegistrationIsNotTheExactStoredRegistration() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            _ = try await mediaRegister(f.store.base, registration: .init(destination: f.registration.server.registration.destination,
                id: .init(rawValue: "\u{e9}"), generation: .init(rawValue: 2)))
            let stored = try #require(try await mediaSnapshot(f.store).registrations.last)
            let alias = DeviceRegistration(server: .init(intent: stored.server.intent, registration: .init(
                destination: stored.server.registration.destination, id: .init(rawValue: "e\u{301}"), generation: stored.server.registration.generation)),
                intentCommit: stored.intentCommit, commit: stored.commit)
            #expect(alias == stored && !PublicationStoreBoundary.exact(alias, stored))
            let coordinator = BackendStatusSynchronizationCoordinator(store: f.store, identity: f.identity, registration: alias,
                remote: f.remote, invalidations: f.invalidations)
            #expect(await coordinator.synchronize().phase == .unavailable)
            #expect(f.remote.afters.isEmpty && f.remote.manifestCalls.isEmpty)
        }
    }
}

@MainActor func statusInvalidator(store: any MediaOperationStorePort & OriginalStorePort, identity: RegistrationStoreIdentity,
                                run: ExplorationRunDirectory) -> MediaInvalidationCoordinator {
    .init(store: store, identity: identity, ordering: ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run)),
          scopes: RenditionScopeRegistry(leases: RenditionReadLeases(store: store)), external: PublicationExternalFixture())
}

nonisolated struct StatusSynchronizationAbsentFiles: RecordingOriginalFilePort {
    func reserveForRecording(_ reference: CaptureOriginalReference) async throws { throw BackendContractError.unavailable }
    func observeFile(_ reference: CaptureOriginalReference) async -> OriginalFileObservation { .absent }
}
