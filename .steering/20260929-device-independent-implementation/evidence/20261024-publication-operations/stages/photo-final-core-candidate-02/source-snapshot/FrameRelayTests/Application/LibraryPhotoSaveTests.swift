import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct LibraryPhotoSaveTests {
    @Test func mixedSelectionFixesLocalAndRemoteTargetsWithoutInventingAnOriginalReference() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make(locals: [true, false, false])
        let port = LibraryPhotoCommandProbe(), model = LibraryModel(reader: f.services.reader, photoSaves: port)
        await model.refresh()
        let snapshot = try #require(model.snapshot), local = try #require(snapshot.recordings.first)
        let first = snapshot.remoteItems[0], second = snapshot.remoteItems[1]
        model.select(local.id, selected: true); model.selectRemotePhoto(first.id, selected: true)
        #expect(model.photoSaveAvailability(captures: model.selected, remotes: model.remotePhotoSelected) == .available)
        let submit = Task { await model.submitPhotos(captures: model.selected, remotes: model.remotePhotoSelected) }
        #expect(await photoBatchEventually { !port.requests.isEmpty })
        model.select(local.id, selected: false)
        model.selectRemotePhoto(first.id, selected: false); model.selectRemotePhoto(second.id, selected: true)
        await model.submitPhotos(captures: model.selected, remotes: model.remotePhotoSelected)
        #expect(port.requests.count == 1)
        let request = port.requests[0]
        #expect(request.displayedRevision == snapshot.revision && request.targets.count == 2)
        #expect(request.targets[0] == .init(original: try #require(local.original), destination: nil))
        #expect(request.targets[1] == .init(original: first.original, destination: first.destination))
        #expect(model.selected.isEmpty && model.remotePhotoSelected == [second.id])
        port.finish(.accepted); await submit.value
        #expect(model.photoSaveMessage?.contains("登録成功ではありません") == true)
        #expect(model.submissions.isEmpty && model.pendingPhotoAcceptance == nil)
        #expect(try await mediaSnapshot(f.services.store).photoSaveBatches.isEmpty)
        #expect(await f.photos.commands.isEmpty)
        // Remote selection never enters the old original/removal command path.
        #expect(model.availability(.cleanup, captures: model.selected) != .available)
    }

    @Test func unknownAcceptanceRetainsTheExactSetForExplicitLookupAndRefreshDoesNotSubmit() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let port = LibraryPhotoCommandProbe(), model = LibraryModel(reader: f.services.reader, photoSaves: port)
        await model.refresh()
        let row = try #require(model.snapshot?.remoteItems.first)
        let submit = Task { await model.submitPhotos(captures: [], remotes: [row.id]) }
        #expect(await photoBatchEventually { port.requests.count == 1 })
        let first = port.requests[0]
        port.finish(.unknown); await submit.value
        await model.refresh()
        #expect(port.requests.count == 1 && model.pendingPhotoAcceptance == first)
        let lookup = Task { await model.reconcilePhotoAcceptance() }
        #expect(await photoBatchEventually { port.requests.count == 2 })
        #expect(port.requests[1] == first)
        port.finish(.accepted); await lookup.value
        #expect(model.pendingPhotoAcceptance == nil)
        #expect(await f.photos.commands.isEmpty)
    }

    @Test func remotePhotoHistoryRequiresExactOriginalAndDestinationAndAllNewFieldsAffectEquality() throws {
        let identifier = try PhotoAssetIdentifier(rawValue: "fixed-photo-identifier")
        let record = try libraryPhotoFixtureRecord(capture: .init(rawValue: "remote-history"),
            outcome: .unknown(localIdentifier: identifier))
        let original = record.registration.intent.rendition.original
        let destination = record.registration.mediaUse.lease.registration.destination
        let rows = LibraryPhotoSaveProjection.registrations([record], original: original, destination: destination)
        #expect(rows.count == 1 && rows[0].record == record && rows[0].canReconcile)
        #expect(LibraryPhotoSaveProjection.registrations([record], original: original,
            destination: .init(rawValue: "different-destination")).isEmpty)
        let other = OriginalContent(capture: original.capture, generation: .init(rawValue: 2), content: original.content)
        #expect(LibraryPhotoSaveProjection.registrations([record], original: other, destination: destination).isEmpty)
        let base = LibraryRemoteItem(destination: destination, original: original, hasIdentityConflict: false)
        var changed = base; changed.photoRegistrations = rows
        #expect(changed != base)
        changed = base; changed.photoSaveUnavailableReason = "受付済み"
        #expect(changed != base)
        let source = PhotoSaveSource(storeIdentity: .init(rawValue: UUID()),
            registration: record.registration.mediaUse.lease.registration, rendition: record.registration.intent.rendition,
            media: record.registration.intent.media, capturedAt: record.registration.intent.capturedAt,
            directoryIdentity: .init(device: 1, inode: 2), fileIdentity: .init(device: 1, inode: 3),
            leaf: UUID().uuidString + ".mov", contentType: "video/quicktime")
        changed = base; changed.photoSaveSource = source
        #expect(changed != base)
    }

    @Test func noWiFiAndUnacquiredRowsCannotSubmitEvenWhenSelectionsExist() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let port = LibraryPhotoSaveCommands(coordinator: f.coordinator(), network: f.network)
        let model = LibraryModel(reader: f.services.reader, photoSaves: port)
        await model.refresh()
        let row = try #require(model.snapshot?.remoteItems.first)
        f.network.set(.cellular)
        #expect(model.photoSaveAvailability(captures: [], remotes: [row.id]).reason == PhotoSaveBatchCoordinator.wifiReason)
        let before = try await mediaSnapshot(f.services.store)
        await model.submitPhotos(captures: [], remotes: [row.id])
        #expect(try await mediaSnapshot(f.services.store) == before)
        #expect(await f.photos.commands.isEmpty)
        var absent = row; absent.photoSaveSource = nil; absent.photoSaveUnavailableReason = LocalRenditionSelection.unavailableReason
        let unavailable = LibraryModel(reader: LibraryPhotoFixedReader(snapshot: .init(revision: before.revision,
            items: [], remoteItems: [absent])), photoSaves: port)
        await unavailable.refresh(); f.network.set(.wiFi)
        #expect(unavailable.photoSaveAvailability(captures: [], remotes: [absent.id]).reason == LocalRenditionSelection.unavailableReason)
        await unavailable.submitPhotos(captures: [], remotes: [absent.id])
        #expect(try await mediaSnapshot(f.services.store) == before)
    }
}

@MainActor private final class LibraryPhotoCommandProbe: LibraryPhotoSavePort {
    private(set) var requests: [PhotoSaveBatchRequest] = []
    private var continuation: CheckedContinuation<LibraryCommandResponse, Never>?
    func availability(sources: [PhotoSaveSource], reasons: [String?]) -> LibraryActionAvailability { .available }
    @MainActor func submit(_ request: PhotoSaveBatchRequest) async -> LibraryCommandResponse {
        requests.append(request)
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ response: LibraryCommandResponse) { continuation?.resume(returning: response); continuation = nil }
    func resume(_ batch: MediaOperationID) async {}
    func cancel(_ batch: MediaOperationID) async {}
    func retry(source: PhotoSaveSource, previous: MediaOperationID, operation: MediaOperationID) async -> LibraryCommandResponse { .unknown }
}

private actor LibraryPhotoFixedReader: LibraryReadPort {
    let snapshot: LibrarySnapshot
    init(snapshot: LibrarySnapshot) { self.snapshot = snapshot }
    func loadLibrary() -> LibraryLoadResult { .loaded(snapshot) }
}
