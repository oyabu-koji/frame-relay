import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct LibraryPublicationProjectionTests {
    @Test func localUnknownSaveAndRemoteMetadataRetainIndependentAxesAcrossReopen() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            _ = try await statusKnownOriginal(f.originals[0], store: f.store)
            let v1 = statusRendition(f.originals[0])
            f.set(.init(current: v1, revision: 1, invalidationGeneration: .init(rawValue: 0),
                replacementPending: true, mediaType: "video/quicktime"))
            #expect(await f.coordinator(run: run).synchronize().phase == .checked)
            let reopened = try statusSynchronizationDisk(.sqlite, run: run, mode: .openExisting)
            guard case .loaded(let library) = await LibraryStoreReader(store: reopened,
                files: StatusSynchronizationAbsentFiles()).loadLibrary() else { throw BackendContractError.unavailable }
            let item = try #require(library.items.first)
            #expect(library.remoteItems.isEmpty && library.history.isEmpty)
            #expect(item.status(.save).contains("保存結果不明") && item.status(.original) == "原本なし")
            #expect(item.status(.publication).contains("公開版ID：" + v1.rendition.rawValue))
            #expect(item.status(.publication).contains("公開世代：1・観測版：1・失効世代：0"))
            #expect(item.status(.publication).contains("置換待ち") && item.status(.publication).contains("video/quicktime"))
            #expect(item.status(.retrieval).contains("オフライン再生不可"))
            #expect(item.status(.confirmation).contains("明示確認なし"))
        }
    }

    @Test func currentRegistrationDoesNotInheritTheOldManifestOrConfirmation() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            let v1 = statusRendition(f.originals[0])
            _ = try await f.commit(f.observation(.init(current: v1, revision: 1,
                invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: "video/quicktime")))
            _ = try await mediaRegister(f.store, registration: .init(destination: f.registration.server.registration.destination,
                id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
            let current = try #require(try await mediaSnapshot(f.store).registrations.last)
            _ = try await inventoryCommit(f.store, inventoryObservation(f.identity, current, originals: f.originals))
            guard case .loaded(let library) = await LibraryStoreReader(store: f.store,
                files: StatusSynchronizationAbsentFiles()).loadLibrary() else { throw BackendContractError.unavailable }
            let row = try #require(library.remoteItems.first)
            #expect(library.items.isEmpty && library.history.isEmpty)
            #expect(row.publicationDescription == "公開版の保存記録なし（未照合を含む）")
            #expect(!row.publicationDescription.contains(v1.rendition.rawValue))
            #expect(row.retrievalDescription.contains("オフライン再生不可"))
            #expect(try await mediaSnapshot(f.store).publicationManifests.count == 1)
        }
    }

    @Test func invalidatedV1IsStillIdentifiableWhileItsPlaybackRemainsUnavailable() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let record = statusInvalidation(f.renditions[0], registration: f.registration.server.registration)
            f.remote.pages = [.succeeded(.init(records: [record], nextAfter: nil))]
            f.remote.setManifest(f.renditions[0], revision: 1, generation: 1)
            #expect(await f.coordinator().synchronize().phase == .checked)
            let snapshot = try await mediaSnapshot(f.store)
            let status = LibraryPublicationProjection.statuses(original: f.renditions[0].original,
                registration: record.registration, backend: snapshot)
            #expect(status.publication.contains(f.renditions[0].rendition.rawValue))
            #expect(status.retrieval.contains("失効済み・再生に利用できません"))
            #expect(snapshot.confirmationStates.first?.validConfirmation == nil)
            #expect(snapshot.publications.count == 1 && snapshot.confirmations.isEmpty)
        }
    }

    @Test func onlyTheExactCurrentVersionCanContributeACompleteRetrievalRecord() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run)
            let v1 = statusRendition(f.originals[0]), v2 = statusRendition(f.originals[0], version: 2)
            _ = try await f.commit(f.observation(.init(current: v2, revision: 2,
                invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: "video/quicktime")))
            var snapshot = try await mediaSnapshot(f.store)
            func media(_ rendition: RenditionIdentity) throws -> TemporaryMediaState {
                .init(id: .init(rawValue: "projection-only-copy"), rendition: rendition,
                    registration: f.registration.server.registration, capturedAt: Date(timeIntervalSince1970: 100),
                    leaf: "projection-only.mov", contentType: "video/quicktime",
                    directoryIdentity: .init(device: 1, inode: 2), fileIdentity: .init(device: 1, inode: 3),
                    ranges: [try .init(lowerBound: 0, upperBound: rendition.deliveryContent.byteCount)],
                    verifiedContent: rendition.deliveryContent)
            }
            snapshot.temporaryMedia = [try media(v1)]
            let old = LibraryPublicationProjection.statuses(original: f.originals[0],
                registration: f.registration.server.registration, backend: snapshot)
            #expect(old.retrieval.contains("オフライン再生不可"))
            snapshot.temporaryMedia = [try media(v2)]
            let current = LibraryPublicationProjection.statuses(original: f.originals[0],
                registration: f.registration.server.registration, backend: snapshot)
            #expect(current.retrieval.contains("完全取得の記録あり"))
            #expect(current.retrieval.contains("実媒体の照合が必要"))
            #expect(!current.retrieval.contains("再生可能"))
            #expect(try await mediaSnapshot(f.store).temporaryMedia.isEmpty)
        }
    }
}
