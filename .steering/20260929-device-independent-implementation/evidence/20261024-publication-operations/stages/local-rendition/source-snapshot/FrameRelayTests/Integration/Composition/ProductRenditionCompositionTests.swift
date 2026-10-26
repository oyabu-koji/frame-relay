import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct ProductRenditionCompositionTests {
    @Test func ordinaryRemoteRowPlaysRealLocalMovieStopsReclaimsThenExplicitlyConfirmsAndReopens() async throws {
        let f = try await ProductRenditionFixture.make()
        let composition = ProductComposition(factory: f.libraryFactory)
        await composition.open()
        let library = try #require(composition.library), model = try #require(composition.renditionPlayback)
        let row = try #require(library.snapshot?.remoteItems.first)
        #expect(library.remotePlaybackAvailability(row) == .available)
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
        await library.playRemoteRendition(row)
        #expect(await renditionEventually { model.token != nil && (model.playback?.decodedFrames ?? 0) > 0 })
        let token = try #require(model.token), player = try #require(model.playback)
        #expect(token.distribution == f.distribution && player.audioTracks == 1)
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
        await model.stop()
        #expect(player.phase == .stopped && player.sdkDetached && player.player == nil)
        #expect(player.startedMonitors == player.completedMonitors && model.token == token)
        let stopped = try await mediaSnapshot(f.services.store)
        #expect(stopped.temporaryMedia.first?.reclaimed == true && !FileManager.default.fileExists(atPath: f.mediaURL.path))
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
        await model.confirm()
        let confirmed = try await mediaSnapshot(f.services.store)
        #expect(confirmed.confirmations.count == 1 && confirmed.outbox == [.confirmation(confirmed.confirmations[0])])
        #expect(confirmed.confirmations[0].intent.playback == token)
        await model.close()
        #expect(model.target == nil && model.token == nil && model.session == nil)
        let reopened = try SQLiteRecordingStore(run: f.services.run, mode: .openExisting)
        let durable = try await mediaSnapshot(reopened)
        #expect(durable.confirmations == confirmed.confirmations && durable.outbox == confirmed.outbox)
        #expect(durable.confirmationStates.first?.validConfirmation == confirmed.confirmations[0])
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
    }

    @Test(arguments: ["missing-root", "missing-lock", "missing-file", "replaced-root", "replaced-file", "changed-bytes"])
    func actualMissingOrChangedCacheIsRejectedWithoutCreatingOrRepairingIt(mode: String) async throws {
        let f = try await ProductRenditionFixture.make()
        switch mode {
        case "missing-root": try FileManager.default.moveItem(at: f.root, to: f.root.appendingPathExtension("preserved"))
        case "missing-lock": try FileManager.default.moveItem(at: f.root.appendingPathComponent("owner.lock"),
            to: f.root.appendingPathComponent("preserved-lock"))
        case "missing-file": try FileManager.default.moveItem(at: f.mediaURL, to: f.mediaURL.appendingPathExtension("preserved"))
        case "replaced-root":
            let preserved = f.root.appendingPathExtension("preserved")
            try FileManager.default.moveItem(at: f.root, to: preserved)
            try FileManager.default.copyItem(at: preserved, to: f.root)
        case "replaced-file":
            try FileManager.default.moveItem(at: f.mediaURL, to: f.mediaURL.appendingPathExtension("preserved"))
            try f.bytes.write(to: f.mediaURL, options: .withoutOverwriting)
        default:
            var changed = f.bytes; changed[changed.startIndex] ^= 1
            try changed.write(to: f.mediaURL)
        }
        let factory = f.factory()
        do { _ = try await factory.prepare(f.target); Issue.record("Changed physical cache must not be admitted") }
        catch {}
        if mode == "missing-root" { #expect(!FileManager.default.fileExists(atPath: f.root.path)) }
        if mode == "missing-lock" { #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("owner.lock").path)) }
        if mode == "missing-file" { #expect(!FileManager.default.fileExists(atPath: f.mediaURL.path)) }
        let snapshot = try await mediaSnapshot(f.services.store)
        #expect(snapshot.confirmations.isEmpty && snapshot.outbox.isEmpty)
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
    }

    @Test func missingLocalOriginalDoesNotPreventIndependentCompleteRenditionPlayback() async throws {
        let f = try await ProductRenditionFixture.make(local: true)
        let reference = try #require(f.localReference)
        let originalURL = try await f.services.originals.existingURL(for: reference)
        let digest = try await f.services.originals.digest(for: reference)
        #expect(digest.byteCount == f.original.content.byteCount && digest.sha256 == f.original.content.digest)
        #expect(await f.services.originals.observeFile(reference) == .present(byteCount: f.original.content.byteCount))
        let preserved = originalURL.appendingPathExtension("preserved")
        try #require(!FileManager.default.fileExists(atPath: preserved.path))
        try FileManager.default.moveItem(at: originalURL, to: preserved)
        #expect(await f.services.originals.observeFile(reference) == .absent)
        let composition = ProductComposition(factory: f.libraryFactory)
        await composition.open()
        let library = try #require(composition.library), model = try #require(composition.renditionPlayback)
        #expect(library.item(f.original.capture)?.status(.original) == "原本なし")
        #expect(library.availability(.playRendition, captures: [f.original.capture]) == .available)
        await library.submit(.playRendition, captures: [f.original.capture])
        #expect(await renditionEventually { model.token != nil })
        await model.close()
        let preservedBytes = try Data(contentsOf: preserved), sourceBytes = try Data(contentsOf: f.sourceURL)
        #expect(preservedBytes == f.bytes && sourceBytes == f.bytes)
    }

    @Test func invalidationAndLaterPublicationRejectTheOldCompleteCopyWithoutReusingIt() async throws {
        let f = try await ProductRenditionFixture.make()
        let termination = ProductMediaTermination(store: f.services.store, access: f.services.access,
            player: AVOriginalPlayback(access: f.services.access))
        let invalidations = await termination.invalidationCoordinator(identity: f.identity)
        let record = statusInvalidation(f.rendition, registration: f.registration)
        guard case .succeeded = await invalidations.invalidate(record) else { throw BackendContractError.notCommitted }
        let scopes = await termination.scopes
        let factory = f.factory(scopes: scopes)
        do { _ = try await factory.prepare(f.target); Issue.record("Invalidated local copy must not play") } catch {}
        let next = statusRendition(f.original, version: 2)
        _ = try await mediaCommit(f.services.store, .publication(mediaPublication(next,
            registration: f.registration, observation: 2, generation: 1)))
        do { _ = try await factory.prepare(f.target); Issue.record("The old copy must not supply the new version") } catch {}
        #expect(try Data(contentsOf: f.mediaURL) == f.bytes)
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
        #expect(await factory.openedOwners == 0)
    }

    @Test func selectionRequiresPositiveDurableProofCurrentRegistrationAndCompleteCoverage() async throws {
        let f = try await ProductRenditionFixture.make()
        let original = try await mediaOriginalSnapshot(f.services.store)
        let before = try await mediaSnapshot(f.services.store)
        var snapshot = before; snapshot.distributionObservations = []
        #expect(throws: BackendContractError.self) { try LocalRenditionSelection.select(backend: snapshot, originals: original, target: f.target) }
        snapshot = before; snapshot.temporaryMedia[0].ranges = []
        #expect(throws: BackendContractError.self) { try LocalRenditionSelection.select(backend: snapshot, originals: original, target: f.target) }
        _ = try await mediaRegister(f.services.store, registration: .init(destination: f.registration.destination,
            id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
        do { _ = try await f.factory().prepare(f.target); Issue.record("Old registration must not be reused") } catch {}
        #expect(try Data(contentsOf: f.mediaURL) == f.bytes)
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
    }

    @Test func concurrentOpenJoinsOneOwnerAndClosedScopeIsNeverReused() async throws {
        let f = try await ProductRenditionFixture.make()
        let factory = f.factory()
        async let openingA = factory.openOwner(f.target)
        async let openingB = factory.openOwner(f.target)
        let (ownerA, ownerB) = try await (openingA, openingB)
        #expect(ownerA.player === ownerB.player && ownerA.scope === ownerB.scope)
        #expect(await factory.openedOwners == 1)
        let a = try await factory.prepare(f.target)
        // A controlled unknown Photos result retains this dedicated copy under
        // the existing policy; it is not a PhotoKit or formal-producer success.
        guard case .succeeded(let photoUse) = await a.owner.temporary.acquireUsage(f.media, purpose: .photoHandoff,
            usageID: .init(rawValue: UUID().uuidString)) else { throw BackendContractError.unavailable }
        let photo = try await a.owner.temporary.stateFor(f.media).receipt(for: photoUse)
        let photos = PhotoSaveLibrary()
        await photos.configure(add: .authorized, outcome: .unknown(localIdentifier: nil))
        let save = PhotoSaveCoordinator(store: f.services.store, identity: f.identity,
            temporaryMedia: a.owner.temporary, library: photos)
        guard case .succeeded = await save.save(photo, action: .init(rawValue: UUID().uuidString)) else {
            throw BackendContractError.notCommitted
        }
        #expect(await factory.release(a))
        _ = try await a.owner.scope.close()
        let c = try await factory.prepare(f.target)
        #expect(c.owner.player !== a.owner.player && c.owner.scope !== a.owner.scope)
        #expect(await factory.openedOwners == 2)
        #expect(await factory.release(c))
        #expect(try Data(contentsOf: f.mediaURL) == f.bytes)
        #expect(try await mediaSnapshot(f.services.store).photoRegistrations.first?.outcome == .unknown(localIdentifier: nil))
    }

    @Test func oldUnknownUseIsPreservedWhileNewPlaybackUseStopsAndGlobalAckRemainsUnknown() async throws {
        let f = try await ProductRenditionFixture.make()
        let leases = RenditionReadLeases(store: f.services.store)
        let state = try #require(try await mediaSnapshot(f.services.store).temporaryMedia.first)
        let old = try await leases.acquireTemporary(state, purpose: .playback, usageID: .init(rawValue: "old-unknown-use"),
            owner: "persisted-unknown-owner")
        let termination = ProductMediaTermination(store: f.services.store, access: f.services.access,
            player: AVOriginalPlayback(access: f.services.access))
        let scopes = await termination.scopes
        let factory = f.factory(scopes: scopes)
        let model = RenditionPlaybackModel(factory: factory)
        #expect(model.open(f.target))
        #expect(await renditionEventually { model.token != nil })
        await model.stop()
        let after = try #require(try await mediaSnapshot(f.services.store).temporaryMedia.first)
        #expect(after.usages == [old] && !after.reclaimed && !after.reclaiming)
        #expect(try Data(contentsOf: f.mediaURL) == f.bytes)
        let invalidations = await termination.invalidationCoordinator(identity: f.identity)
        let record = statusInvalidation(f.rendition, registration: f.registration)
        #expect(await invalidations.invalidate(record) == .unknown)
        let retained = try await mediaSnapshot(f.services.store)
        #expect(retained.invalidations.isEmpty && retained.outbox.isEmpty)
        #expect(retained.temporaryMedia.first?.usages == [old])
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals.first?.mediaReaders == [old.lease])
        await model.close()
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
    }
}
