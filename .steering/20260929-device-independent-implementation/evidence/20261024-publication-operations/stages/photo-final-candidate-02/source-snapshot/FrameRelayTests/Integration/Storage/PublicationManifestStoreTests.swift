import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct PublicationManifestStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func completeManifestHistorySurvivesDiskReopenWithoutCreatingAuthority(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run, candidate: candidate)
            let v1 = statusRendition(f.originals[0]), v2 = statusRendition(f.originals[0], version: 2)
            let values: [PublicationManifest] = [
                .init(current: nil, revision: 0, invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: nil),
                .init(current: v1, revision: 1, invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: "video/quicktime"),
                .init(current: v1, revision: 1, invalidationGeneration: .init(rawValue: 0), replacementPending: true, mediaType: "video/quicktime"),
                .init(current: v1, revision: 1, invalidationGeneration: .init(rawValue: 1), replacementPending: true, mediaType: "video/quicktime"),
                .init(current: v2, revision: 2, invalidationGeneration: .init(rawValue: 1), replacementPending: false, mediaType: "video/mp4")
            ]
            var observations: [PublicationManifestObservation] = []
            for value in values {
                let observation = f.observation(value)
                _ = try await f.commit(observation)
                observations.append(observation)
            }
            let reopened = try statusSynchronizationDisk(candidate, run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.publicationManifests.map(\.observation) == observations)
            let allCommitted = snapshot.publicationManifests.allSatisfy { $0.isCommitted }
            #expect(allCommitted)
            #expect(snapshot.publications.isEmpty && snapshot.confirmationStates.isEmpty && snapshot.confirmations.isEmpty)
            #expect(snapshot.invalidations.isEmpty && snapshot.outbox.isEmpty && snapshot.requests.isEmpty)
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.isEmpty)
            guard case .loaded(let library) = await LibraryStoreReader(store: reopened,
                files: StatusSynchronizationAbsentFiles()).loadLibrary() else { throw BackendContractError.unavailable }
            let row = try #require(library.remoteItems.first)
            #expect(library.items.isEmpty && row.publicationDescription.contains(v2.rendition.rawValue))
            #expect(row.publicationDescription.contains("video/mp4") && row.publicationDescription.contains("観測版：2"))
            #expect(row.retrievalDescription.contains("オフライン再生不可"))
            #expect(try await mediaSnapshot(reopened) == snapshot)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func exactMutationResolvesRealDiskCommitFaultWithoutRebasing(candidate: StorageCandidate, fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run, candidate: candidate)
            let before = try await mediaSnapshot(f.store)
            let observation = f.observation(.init(current: nil, revision: 0, invalidationGeneration: .init(rawValue: 0),
                replacementPending: false, mediaType: nil))
            let mutation = BackendStoreMutation(expectedRevision: before.revision, change: .publicationManifest(observation),
                expectedStoreIdentity: f.identity)
            let faulty = try statusSynchronizationDisk(candidate, run: run, mode: .openExisting, fault: fault)
            let result = await faulty.commit(mutation)
            #expect(result == (fault == .afterDiskCommitBeforeReply ? .unknown : .unavailable(.inaccessible)))
            let reopened = try statusSynchronizationDisk(candidate, run: run, mode: .openExisting)
            let after = try await mediaSnapshot(reopened)
            if fault == .afterDiskCommitBeforeReply {
                let record = try #require(after.publicationManifests.first)
                #expect(await reopened.lookupCommit(mutation) == .committed(record.commit))
                #expect(await reopened.lookupCommit(.init(expectedRevision: mutation.expectedRevision + 1,
                    change: mutation.change, expectedStoreIdentity: f.identity)) == .rejected(.identityMismatch))
            } else {
                #expect(after == before)
                #expect(await reopened.lookupCommit(mutation) == .unknown)
            }
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func byteDistinctPayloadAndWrongStoreCannotBorrowAnExistingReceipt(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run, candidate: candidate,
                names: ["\u{e9}", "e\u{301}"])
            let value = f.observation(.init(current: nil, revision: 0, invalidationGeneration: .init(rawValue: 0),
                replacementPending: false, mediaType: nil))
            let before = try await mediaSnapshot(f.store)
            let mutation = BackendStoreMutation(expectedRevision: before.revision, change: .publicationManifest(value),
                expectedStoreIdentity: f.identity)
            guard case .committed = await f.store.commit(mutation) else { throw BackendContractError.notCommitted }
            let alias = PublicationManifestObservation(command: value.command, storeIdentity: value.storeIdentity,
                registration: value.registration, original: f.originals[1], manifest: value.manifest)
            let changed = BackendStoreMutation(expectedRevision: before.revision, change: .publicationManifest(alias),
                expectedStoreIdentity: f.identity)
            #expect(mutation == changed && !PublicationStoreBoundary.exact(mutation, changed))
            #expect(await f.store.lookupCommit(changed) == .rejected(.identityMismatch))
            #expect(await f.store.commit(changed) == .rejected(.identityMismatch))
            let wrongStore = BackendStoreMutation(expectedRevision: before.revision, change: mutation.change,
                expectedStoreIdentity: .init(rawValue: UUID()))
            #expect(await f.store.lookupCommit(wrongStore) == .rejected(.identityMismatch))
            #expect(await f.store.commit(wrongStore) == .rejected(.identityMismatch))
            #expect(try await mediaSnapshot(f.store).publicationManifests.count == 1)
        }
    }

    @Test func staleSameRevisionConflictingUnknownOriginalAndOldRegistrationAreRejected() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            let v1 = statusRendition(f.originals[0]), v2 = statusRendition(f.originals[0], version: 2)
            let initial = f.observation(.init(current: v1, revision: 4, invalidationGeneration: .init(rawValue: 1),
                replacementPending: true, mediaType: "video/quicktime"))
            _ = try await f.commit(initial)
            let invalid: [PublicationManifest] = [
                .init(current: v1, revision: 3, invalidationGeneration: .init(rawValue: 1), replacementPending: true, mediaType: "video/quicktime"),
                .init(current: v2, revision: 4, invalidationGeneration: .init(rawValue: 1), replacementPending: true, mediaType: "video/quicktime"),
                .init(current: v1, revision: 4, invalidationGeneration: .init(rawValue: 1), replacementPending: false, mediaType: "video/quicktime"),
                .init(current: v1, revision: 5, invalidationGeneration: .init(rawValue: 0), replacementPending: true, mediaType: "video/quicktime"),
                .init(current: v1, revision: 5, invalidationGeneration: .init(rawValue: 1), replacementPending: true, mediaType: nil)
            ]
            for value in invalid {
                let before = try await mediaSnapshot(f.store)
                let result = await f.store.commit(.init(expectedRevision: before.revision,
                    change: .publicationManifest(f.observation(value)), expectedStoreIdentity: f.identity))
                guard case .rejected = result else { Issue.record("Invalid manifest was admitted"); continue }
                #expect(try await mediaSnapshot(f.store) == before)
            }
            let unknown = PublicationManifestObservation(command: .init(rawValue: UUID().uuidString), storeIdentity: f.identity,
                registration: f.registration.server.registration, original: try inventoryOriginal("not-in-inventory"),
                manifest: .init(current: nil, revision: 0, invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: nil))
            #expect(await f.store.commit(.init(expectedRevision: try await mediaSnapshot(f.store).revision,
                change: .publicationManifest(unknown), expectedStoreIdentity: f.identity)) == .rejected(.notCommitted))
            _ = try await mediaRegister(f.store, registration: .init(destination: f.registration.server.registration.destination,
                id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
            #expect(await f.store.commit(.init(expectedRevision: try await mediaSnapshot(f.store).revision,
                change: .publicationManifest(f.observation(initial.manifest)), expectedStoreIdentity: f.identity)) == .rejected(.notCommitted))
        }
    }

    @Test func nilMetadataRetainsPriorPublicationAndExplicitConfirmationAuthority() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let coordinator = MediaConfirmationCoordinator(store: f.store, identity: f.identity)
            guard case .succeeded(let confirmation) = await coordinator.confirm(
                try publicationToken(f.renditions[0], registration: f.registration.server.registration),
                action: .init(rawValue: "explicit-manifest-absence-test")) else { throw BackendContractError.notCommitted }
            let before = try await mediaSnapshot(f.store)
            let value = PublicationManifestObservation(command: .init(rawValue: UUID().uuidString), storeIdentity: f.identity,
                registration: f.registration.server.registration, original: f.renditions[0].original,
                manifest: .init(current: nil, revision: 2, invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: nil))
            guard case .committed = await f.store.commit(.init(expectedRevision: before.revision,
                change: .publicationManifest(value), expectedStoreIdentity: f.identity)) else { throw BackendContractError.notCommitted }
            let after = try await mediaSnapshot(f.store)
            #expect(after.publications == before.publications && after.confirmations == [confirmation])
            #expect(after.confirmationStates.first?.validConfirmation == confirmation)
            #expect(after.invalidations.isEmpty && after.outbox == before.outbox)
        }
    }

    @Test func preManifestSchema7DocumentRemainsReadableWithoutInventingAnObservation() throws {
        let bytes = Data(#"{"schema":7,"storeIdentity":null,"entries":[],"transactionRevision":0,"originalJournal":[],"backendJournal":[],"legacyRevision":0}"#.utf8)
        let document = try RecordingStoreDocument.decode(bytes)
        let state = try document.replayStore().snapshot(revision: document.transactionRevision)
        #expect(state.publicationManifests.isEmpty && state.publications.isEmpty && state.storeIdentity == nil)
        #expect(document.schema == 7 && document.backendJournal.isEmpty)
    }
}
