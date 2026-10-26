import Foundation
import Testing
@testable import FrameRelay

/// The movie, writer, usages, scopes and product invalidation producer are real.
/// Only the Photos callback is controlled; these cases do not establish PhotoKit
/// behavior or the product eligibility/quality of the synthetic rendition.
@Suite(.serialized) @MainActor struct PhotoInvalidationBoundaryTests {
    @Test func durableUnknownPhotoResultSurvivesExactUsageReleaseAndRootClosureBeforeCallerRelease() async throws {
        try await withStorageRun { run in
            let f = try await PhotoInvalidationFixture.make(run: run)
            let outcome = PhotoRegistrationOutcome.unknown(localIdentifier: try .init(rawValue: "s31-terminal-unknown"))
            await f.library.configure(outcome: outcome, delayed: true)
            // Only the PhotoSaveCoordinator's final use-release call is held.
            // The actual scope/root owner continues to call the real temporary
            // adapter so the interleaving is forced without invented receipts.
            let boundary = PhotoCallerReleaseBoundary(base: f.temporary, heldUsage: f.photo.usage)
            let photos = PhotoSaveCoordinator(store: f.store, identity: f.identity,
                temporaryMedia: boundary, library: f.library)
            let caller = Task { await photos.save(f.photo, action: .init(rawValue: "photo-release-after-root-closure")) }
            defer { Task { await boundary.resumeRelease(); await f.library.complete() } }
            try #require(await renditionEventually { await f.library.additions.count == 1 })
            caller.cancel()
            await f.library.complete()
            try #require(await renditionEventually { await boundary.releaseHasArrived() })

            let beforeInvalidation = try await mediaSnapshot(f.store)
            let committed = try #require(beforeInvalidation.photoRegistrations.last)
            #expect(committed.outcome == outcome && committed.localIdentifier == outcome.localIdentifier)
            let sdkTerminal = try #require(committed.usageTerminal)
            #expect(sdkTerminal.terminal.termination == .sdkCompleted)
            #expect(committed.terminalUsageRelease == nil)
            let heldState = try await f.temporary.stateFor(f.photo.id)
            #expect(heldState.usages == [committed.registration.mediaUse])
            let heldUsage = try await f.temporary.usageSnapshot(f.photo.id)
            #expect(heldUsage.uses == 1 && heldUsage.openHandles == 0)
            #expect(await boundary.forwardedResult() == nil)
            #expect(await f.library.completed == 1)

            let invalidations = await f.termination.invalidationCoordinator(identity: f.identity)
            let invalidated = await invalidations.invalidate(f.invalidation)
            guard case .succeeded(let acknowledgement) = invalidated else {
                Issue.record("Real invalidation must release the exact terminal photo use and close owners before resuming the caller: \(invalidated)")
                return
            }
            #expect(acknowledgement.isCommitted && acknowledgement.record == f.invalidation)
            let photoOwner = try await f.photoScope.close()
            let otherOwner = try await f.otherScope.close()
            for owner in [photoOwner, otherOwner] {
                #expect(owner.factoryAdmissionClosed && owner.registeredOwners == 1)
                let actual = try #require(owner.observations.first)
                #expect(actual.owner == .temporaryMedia)
                #expect(actual.terminal.started > 0 && actual.terminal.started == actual.terminal.completed)
                #expect(actual.terminal.handlesClosed)
            }
            let beforeForward = try await mediaSnapshot(f.store)
            let settled = try #require(beforeForward.photoRegistrations.last)
            let release = try #require(settled.terminalUsageRelease)
            #expect(settled.outcome == outcome && settled.localIdentifier == outcome.localIdentifier)
            #expect(settled.registration == committed.registration && settled.usageTerminal == committed.usageTerminal)
            #expect(release.release.terminal == sdkTerminal.terminal)
            #expect(release.commit.committedRevision <= acknowledgement.commit.previousRevision)
            let released = try await f.temporary.stateFor(f.photo.id)
            #expect(released.usages.isEmpty)
            #expect(released.releasedUsages.filter { $0.usage.purpose == .photoHandoff } == [committed.registration.mediaUse])
            #expect(heldState.releasedUsages.allSatisfy { released.releasedUsages.contains($0) })
            #expect(released.releasedUsages.count == heldState.releasedUsages.count + 1)
            #expect(!released.reclaimed && !released.reclaiming)
            #expect(try Data(contentsOf: f.photoURL) == f.bytes)
            #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
            let original = try #require(try await mediaOriginalSnapshot(f.store).logicalOriginals.first(where: {
                $0.original == f.photo.rendition.original
            }))
            #expect(original.readers.isEmpty && original.mediaReaders.isEmpty)
            #expect(beforeForward.invalidations == [acknowledgement] && beforeForward.outbox == [.invalidation(acknowledgement)])

            // The kernel root descriptors are now actually closed. Only now let
            // PhotoSave's same exact release reach the unchanged real adapter.
            await boundary.resumeRelease()
            let returned = await caller.value
            let forwarded = await boundary.forwardedResult()
            let callerPhase: String
            if case .succeeded = returned { callerPhase = "succeeded" }
            else { callerPhase = String(describing: returned) }
            print("S31_PHOTO_RELEASE_ORDER callback=completed callerCancelled=true root=closed exactUse=durably-released ack=committed baseRelease=\(String(describing: forwarded)) caller=\(callerPhase)")
            let after = try await mediaSnapshot(f.store)
            #expect(after.photoRegistrations == beforeForward.photoRegistrations)
            #expect(after.invalidations == beforeForward.invalidations && after.outbox == beforeForward.outbox)
            #expect(try Data(contentsOf: f.photoURL) == f.bytes)
            let additions = await f.library.additions.count
            let completed = await f.library.completed
            #expect(additions == 1 && completed == 1)
            #expect(forwarded == .succeeded(f.photo.id),
                "An exact, already committed terminal-use release must remain idempotent after its own root closed")
            if case .succeeded(let result) = returned {
                #expect(result == settled)
            } else {
                Issue.record("The committed unknown Photos outcome and identifier must survive the late exact caller release; baseRelease=\(String(describing: forwarded)), caller=\(returned)")
            }
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).photoRegistrations == [settled])
        }
    }

    @Test(arguments: [PhotoRegistrationOutcome.succeeded(localIdentifier: try! .init(rawValue: "s31-terminal-success")),
                      .failed(.rejected), .unknown(localIdentifier: nil),
                      .unknown(localIdentifier: try! .init(rawValue: "s31-terminal-unknown"))], [false, true])
    func photoCallbackMustEndBeforeEveryScopeAndInvalidationCanCommit(outcome: PhotoRegistrationOutcome,
                                                                    cancelCaller: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PhotoInvalidationFixture.make(run: run)
            await f.library.configure(outcome: outcome, delayed: true)
            let action = MediaOperationID(rawValue: "explicit-photo-save-before-invalidation")
            let caller = Task { await f.photos.save(f.photo, action: action) }
            defer { Task { await f.library.complete() } }
            try #require(await renditionEventually { await f.library.additions.count == 1 })

            let originalRecord = try #require(try await mediaSnapshot(f.store).photoRegistrations.last)
            #expect(originalRecord.registration.intent.usage == f.photo.usage)
            #expect(originalRecord.registration.isCommitted)
            let invalidations = await f.termination.invalidationCoordinator(identity: f.identity)
            let invalidation = Task { await invalidations.invalidate(f.invalidation) }
            try #require(await renditionEventually {
                guard let snapshot = try? await mediaOriginalSnapshot(f.store) else { return false }
                return snapshot.logicalOriginals.first(where: {
                    $0.original == f.photo.rendition.original
                })?.invalidation?.record == f.invalidation
            })
            if cancelCaller { caller.cancel() }

            let pending = try await mediaSnapshot(f.store)
            #expect(pending.invalidations.isEmpty && pending.outbox.isEmpty)
            #expect(pending.photoRegistrations.last?.outcome == nil)
            #expect(pending.photoRegistrations.last?.usageTerminal == nil)
            #expect(await f.library.completed == 0)
            #expect(await f.library.fileBytes == f.bytes)
            let held = try await f.temporary.usageSnapshot(f.photo.id)
            #expect(held.uses == 1 && held.openHandles == 1)
            #expect(held.fileBytes == UInt64(f.bytes.count))
            let heldState = try await f.temporary.stateFor(f.photo.id)
            #expect(heldState.usages == [originalRecord.registration.mediaUse])
            let heldOriginal = try #require(try await mediaOriginalSnapshot(f.store).logicalOriginals.first(where: {
                $0.original == f.photo.rendition.original
            }))
            #expect(heldOriginal.mediaReaders.contains(originalRecord.registration.mediaUse.lease))
            #expect(try Data(contentsOf: f.photoURL) == f.bytes)

            await f.library.complete()
            guard case .succeeded(let saved) = await caller.value else {
                Issue.record("Caller cancellation or invalidation discarded the terminal Photos result")
                return
            }
            #expect(saved.outcome == outcome)
            #expect(saved.localIdentifier == outcome.localIdentifier)
            #expect(await f.library.completed == 1)

            // An early reconciliation may report unknown while Photos owns the
            // handle. Resume that exact durable reservation after its callback.
            let first = await invalidation.value
            let result = first == .unknown ? await invalidations.invalidate(f.invalidation) : first
            guard case .succeeded(let acknowledgement) = result else {
                Issue.record("Exact invalidation did not reconcile after Photos terminated")
                return
            }
            #expect(acknowledgement.record == f.invalidation)
            #expect(acknowledgement.isCommitted)

            let settled = try #require(try await mediaSnapshot(f.store).photoRegistrations.last)
            #expect(settled.registration == originalRecord.registration)
            #expect(settled.outcome == outcome)
            #expect(settled.localIdentifier == outcome.localIdentifier)
            let terminalProof = try #require(settled.usageTerminal)
            #expect(terminalProof.terminal.termination == .sdkCompleted)
            #expect(terminalProof.terminal.mediaUse == originalRecord.registration.mediaUse)
            #expect(terminalProof.commit.committedRevision <= acknowledgement.commit.previousRevision)
            let released = try await f.temporary.stateFor(f.photo.id)
            #expect(released.usages.isEmpty)
            #expect(released.releasedUsages.contains(originalRecord.registration.mediaUse))
            #expect(released.releasedUsages.filter { $0.usage.purpose == .photoHandoff } == [originalRecord.registration.mediaUse])
            if case .succeeded = outcome {
                #expect(released.reclaimed)
                #expect(!FileManager.default.fileExists(atPath: f.photoURL.path))
            } else {
                let releaseProof = try #require(settled.terminalUsageRelease)
                #expect(releaseProof.release.terminal == terminalProof.terminal)
                #expect(releaseProof.commit.committedRevision <= acknowledgement.commit.previousRevision)
                #expect(!released.reclaiming && !released.reclaimed)
                #expect(try Data(contentsOf: f.photoURL) == f.bytes)
            }
            #expect(try Data(contentsOf: f.sourceURL) == f.bytes)

            let photoTerminal = try await f.photoScope.close()
            let otherTerminal = try await f.otherScope.close()
            for terminal in [photoTerminal, otherTerminal] {
                #expect(terminal.factoryAdmissionClosed && terminal.registeredOwners == 1)
                #expect(terminal.observations.map(\.owner) == [.temporaryMedia])
                let observation = try #require(terminal.observations.first)
                #expect(observation.terminal.started > 0)
                #expect(observation.terminal.started == observation.terminal.completed)
                #expect(observation.terminal.handlesClosed)
            }
            let other = try await f.otherTemporary.stateFor(f.other.id)
            #expect(other.usages.isEmpty && other.reclaimed)
            #expect(!FileManager.default.fileExists(atPath: f.otherURL.path))
            let final = try await mediaSnapshot(f.store)
            #expect(final.invalidations == [acknowledgement])
            #expect(final.outbox == [.invalidation(acknowledgement)])
            #expect(final.confirmationStates.first?.invalidatedRenditions == [f.photo.rendition.rendition])
            let original = try #require(try await mediaOriginalSnapshot(f.store).logicalOriginals.first(where: {
                $0.original == f.photo.rendition.original
            }))
            #expect(original.readers.isEmpty && original.mediaReaders.isEmpty)
            #expect(original.invalidation == nil && original.invalidationGeneration == f.invalidation.generation)

            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let persisted = try await mediaSnapshot(reopened)
            #expect(persisted.invalidations == [acknowledgement])
            #expect(persisted.outbox == [.invalidation(acknowledgement)])
            #expect(persisted.photoRegistrations == [settled])
            #expect(persisted.confirmationStates.first?.invalidatedRenditions == [f.photo.rendition.rendition])
            let next = PhotoSaveCoordinator(store: reopened, identity: f.identity,
                temporaryMedia: f.temporary, library: f.library)
            #expect(await next.save(f.photo, action: .init(rawValue: "unlinked-save-after-reopen")) == .failed(.rejected))
            #expect(await f.library.additions.count == 1)
            #expect(await f.library.requests == [.addOnly])
            #expect(await f.library.lookups.isEmpty)
        }
    }
}

/// This forwarding actor changes scheduling only. Every actual file/SDK/use
/// observation and release still comes from the original temporary adapter.
private actor PhotoCallerReleaseBoundary {
    private let base: ManagedTemporaryMedia
    private let heldUsage: TemporaryMediaUsage
    private var arrived = false
    private var resumed = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var result: BackendOutcome<TemporaryMediaID>?

    init(base: ManagedTemporaryMedia, heldUsage: TemporaryMediaUsage) {
        self.base = base; self.heldUsage = heldUsage
    }
    func releaseHasArrived() -> Bool { arrived }
    func forwardedResult() -> BackendOutcome<TemporaryMediaID>? { result }
    func resumeRelease() {
        resumed = true
        continuation?.resume(); continuation = nil
    }
    func inspect(_ id: TemporaryMediaID) async -> BackendOutcome<TemporaryMediaReceipt> { await base.inspect(id) }
    func acquireUsage(_ id: TemporaryMediaID, purpose: TemporaryMediaPurpose,
        usageID: MediaUsageID) async -> BackendOutcome<TemporaryMediaUsage> {
        await base.acquireUsage(id, purpose: purpose, usageID: usageID)
    }
    func releaseUsage(_ usage: TemporaryMediaUsage) async -> BackendOutcome<TemporaryMediaID> {
        if usage == heldUsage {
            arrived = true
            if !resumed { await withCheckedContinuation { continuation = $0 } }
        }
        let actual = await base.releaseUsage(usage)
        if usage == heldUsage { result = actual }
        return actual
    }
    func resolvePhotoMedia(_ usage: TemporaryMediaUsage) async throws -> TemporaryLocalMedia {
        try await base.resolvePhotoMedia(usage)
    }
    func finishPhotoMedia(_ usage: TemporaryMediaUsage) async throws { try await base.finishPhotoMedia(usage) }
    func photoUsageTerminal(_ registration: CommittedPhotoRegistrationIntent,
        termination: PhotoUsageTermination) async throws -> PhotoUsageTerminal {
        try await base.photoUsageTerminal(registration, termination: termination)
    }
}
extension PhotoCallerReleaseBoundary: TemporaryMediaPort, TemporaryLocalMediaPort {}

@MainActor private struct PhotoInvalidationFixture {
    let store: any MediaDiskStore
    let identity: RegistrationStoreIdentity
    let termination: ProductMediaTermination
    let photoScope: RenditionMediaScope
    let temporary: ManagedTemporaryMedia
    let photo: TemporaryMediaReceipt
    let photoURL: URL
    let otherScope: RenditionMediaScope
    let otherTemporary: ManagedTemporaryMedia
    let other: TemporaryMediaReceipt
    let otherURL: URL
    let sourceURL: URL
    let bytes: Data
    let library: PhotoSaveLibrary
    let photos: PhotoSaveCoordinator
    let invalidation: InvalidationRecord

    static func make(run: ExplorationRunDirectory) async throws -> Self {
        let sourceURL = run.url.appendingPathComponent("s31-invalidation-source.mov")
        try await SyntheticMovieFixture.write(to: sourceURL, withAudio: true,
            capturedAt: RenditionFixture.capturedAt)
        let bytes = try Data(contentsOf: sourceURL)
        let rendition = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
        // RenditionFixture's default scope is intentionally outside the product
        // registry. Close that empty owner and create both actual owners below.
        _ = try await rendition.scope.close()
        let access = ManagedOriginalAccess(store: rendition.store, originals: ManagedOriginalStore(run: run))
        let player = AVOriginalPlayback(access: access)
        let termination = ProductMediaTermination(store: rendition.store, access: access, player: player)
        let photoScope = try await termination.scopes.open(original: rendition.command.distribution.rendition.original)
        let photoRoot = run.url.appendingPathComponent("photo-invalidation", isDirectory: true)
        let temporary = try await ManagedTemporaryMedia.open(root: photoRoot, leases: rendition.leases, scope: photoScope)
        let complete = try await completeMovie(bytes, command: rendition.command, temporary: temporary, id: "s31-photo-copy")
        guard case .succeeded(let usage) = await temporary.acquireUsage(complete.id, purpose: .photoHandoff,
            usageID: .init(rawValue: "s31-invalidating-photo-use")) else { throw BackendContractError.unavailable }
        let photo = try await temporary.stateFor(complete.id).receipt(for: usage)
        guard await temporary.releaseUsage(complete.usage) == .succeeded(complete.id) else {
            throw BackendContractError.unknownResult
        }
        let photoState = try await temporary.stateFor(photo.id)
        let photoURL = photoRoot.appendingPathComponent(photoState.leaf)

        let otherScope = try await termination.scopes.open(original: photo.rendition.original)
        let otherRoot = run.url.appendingPathComponent("other-invalidation", isDirectory: true)
        let otherTemporary = try await ManagedTemporaryMedia.open(root: otherRoot, leases: rendition.leases, scope: otherScope)
        let other = try await completeMovie(bytes, command: rendition.command, temporary: otherTemporary, id: "s31-other-copy")
        let otherState = try await otherTemporary.stateFor(other.id)
        let otherURL = otherRoot.appendingPathComponent(otherState.leaf)
        let identity = try await establishRegistrationIdentity(rendition.store)
        let library = PhotoSaveLibrary()
        let photos = PhotoSaveCoordinator(store: rendition.store, identity: identity, temporaryMedia: temporary, library: library)
        let invalidation = InvalidationRecord(id: .init(rawValue: "s31-photo-invalidation"), rendition: photo.rendition,
            registration: rendition.command.distribution.registration, generation: .init(rawValue: 1))
        return .init(store: rendition.store, identity: identity, termination: termination,
            photoScope: photoScope, temporary: temporary, photo: photo, photoURL: photoURL,
            otherScope: otherScope, otherTemporary: otherTemporary, other: other, otherURL: otherURL,
            sourceURL: sourceURL, bytes: bytes, library: library, photos: photos, invalidation: invalidation)
    }

    private static func completeMovie(_ bytes: Data, command: RetrieveMediaCommand,
                                      temporary: ManagedTemporaryMedia, id: String) async throws -> TemporaryMediaReceipt {
        let receipt = try await temporary.create(command: command, id: .init(rawValue: id),
            usageID: .init(rawValue: id + "-playback"), capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
        for offset in stride(from: 0, to: bytes.count, by: 65_536) {
            let end = min(bytes.count, offset + 65_536)
            try await temporary.store(bytes.subdata(in: offset..<end),
                range: .init(lowerBound: UInt64(offset), upperBound: UInt64(end)), using: receipt.usage)
        }
        return try await temporary.verify(receipt.usage)
    }
}
