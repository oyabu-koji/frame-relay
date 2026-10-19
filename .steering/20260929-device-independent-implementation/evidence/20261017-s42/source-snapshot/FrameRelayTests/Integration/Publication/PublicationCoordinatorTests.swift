import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct PublicationCoordinatorTests {
    @Test(arguments: [false, true])
    func explicitConfirmationUnknownCommitKeepsExactMutationAndReopenFacts(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PublicationFixture.make(run: run)
            let coordinator = f.confirmations()
            #expect(await coordinator.restore() == .succeeded([]))
            f.store.stage = .confirmation; f.store.afterCommit = afterCommit; f.store.hideLookup = true
            let action = MediaOperationID(rawValue: "single-user-action")
            #expect(await coordinator.confirm(f.token, action: action) == .unknown)
            let mutation = try #require(f.store.mutations.last)
            _ = try await mediaCommit(f.store.base, .publication(mediaPublication(f.rendition, registration: f.registration, observation: 2)))
            let again = await coordinator.confirm(f.token, action: action)
            if afterCommit { guard case .succeeded = again else { Issue.record("Durable confirmation was not recovered"); return } }
            else {
                #expect(again == .unknown)
                #expect(f.store.lookups.last == mutation)
                #expect(f.store.mutations == [mutation])
            }
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let restored = MediaConfirmationCoordinator(store: reopened, identity: f.identity)
            guard case .succeeded(let records) = await restored.restore() else { Issue.record("Restore failed"); return }
            #expect(records.count == (afterCommit ? 1 : 0))
            #expect(try await mediaSnapshot(reopened).outbox.count == records.count)
            let wrong = MediaConfirmationCoordinator(store: reopened, identity: .init(rawValue: UUID()))
            #expect(await wrong.confirm(f.token, action: .init(rawValue: "wrong-store")) == .unknown)
        }
    }

    @Test func responseLossAndReopenRetireOnlyExactDurableOutbox() async throws {
        try await withStorageRun { run in
            let f = try await PublicationFixture.make(run: run)
            guard case .succeeded(let record) = await f.confirmations().confirm(f.token, action: .init(rawValue: "confirm")) else { Issue.record("Confirmation failed"); return }
            let remote = PublicationRemoteFixture(); remote.loseResponse = true
            remote.credentialsAvailable = false
            let coordinator = BackendOutboxCoordinator(store: f.store, identity: f.identity, remote: remote)
            #expect(await coordinator.synchronize() == .unknown)
            #expect(remote.sent.isEmpty)
            remote.credentialsAvailable = true
            f.store.stage = .delivery; f.store.afterCommit = true; f.store.hideLookup = true
            #expect(await coordinator.synchronize() == .unknown)
            #expect(remote.sent == [.confirmation(record)])
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).outbox.isEmpty)
            #expect(await BackendOutboxCoordinator(store: reopened, identity: f.identity, remote: remote).synchronize() == .succeeded(0))
            #expect(try await mediaSnapshot(reopened).confirmations == [record])
        }
    }

    @Test func invalidationKeepsReservationUntilEveryScopeAndExternalOwnerTerminate() async throws {
        try await withStorageRun { run in
            let f = try await PublicationFixture.make(run: run)
            let leases = RenditionReadLeases(store: f.store)
            let first = try await f.registry.open(original: f.rendition.original)
            let second = try await f.registry.open(original: f.rendition.original)
            let a = try await leases.acquire(rendition: f.rendition, registration: f.registration, operation: .init(rawValue: "a"), context: .transport(.init(rawValue: "a")))
            let b = try await leases.acquire(rendition: f.rendition, registration: f.registration, operation: .init(rawValue: "b"), context: .playback(.init(rawValue: "b")))
            let ownerA = PublicationHeldOwner(lease: a, leases: leases)
            let ownerB = PublicationHeldOwner(lease: b, leases: leases)
            _ = try await first.register(owner: .transport) { try await ownerA.stop() }
            _ = try await second.register(owner: .renditionPlayer) { try await ownerB.stop() }
            let coordinator = f.invalidations()
            let task = Task { await coordinator.invalidate(f.invalidation) }
            #expect(await renditionEventually { ownerA.stopRequested && ownerB.stopRequested })
            #expect(try await mediaSnapshot(f.store).invalidations.isEmpty)
            await #expect(throws: BackendContractError.invalidated) { try await f.registry.open(original: f.rendition.original) }
            ownerA.finishCallback(); ownerB.finishCallback()
            guard case .succeeded(let ack) = await task.value else { Issue.record("All scopes did not reconcile"); return }
            #expect(ack.record == f.invalidation)
            #expect(ownerA.completed && ownerB.completed)
            #expect(try await mediaSnapshot(f.store).outbox == [.invalidation(ack)])
            #expect(await f.ordering.finishInvalidation(ack) == .succeeded(ack.record.id))
            #expect(await f.confirmations().confirm(f.token, action: .init(rawValue: "after-invalidation")) == .failed(.rejected))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).invalidations == [ack])
            #expect(try await mediaSnapshot(reopened).confirmationStates.first?.validConfirmation == nil)
        }
    }

    @Test func unknownExternalAndReregistrationCannotReplaceOldReservation() async throws {
        try await withStorageRun { run in
            let f = try await PublicationFixture.make(run: run)
            f.external.available = false
            let coordinator = f.invalidations()
            #expect(await coordinator.invalidate(f.invalidation) == .unknown)
            let reserved = try await mediaOriginalSnapshot(f.store)
            #expect(reserved.logicalOriginals.first?.invalidation?.record == f.invalidation)
            #expect(await f.ordering.reserveInvalidation(f.invalidation) == .succeeded(.init(record: f.invalidation)))
            #expect(try await mediaOriginalSnapshot(f.store).revision == reserved.revision)
            _ = try await mediaRegister(f.store.base, registration: .init(destination: f.registration.destination, id: .init(rawValue: "next-registration"), generation: .init(rawValue: 2)))
            f.external.available = true
            #expect(await coordinator.invalidate(f.invalidation) == .unknown)
            #expect(try await mediaSnapshot(f.store).invalidations.isEmpty)
            #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals.first?.invalidation?.record == f.invalidation)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.first?.invalidation?.record == f.invalidation)
        }
    }

    @Test func reservedInvalidationResumesAfterReopenWithoutInventingExternalEvidence() async throws {
        try await withStorageRun { run in
            let f = try await PublicationFixture.make(run: run)
            #expect(await f.ordering.reserveInvalidation(f.invalidation) == .succeeded(.init(record: f.invalidation)))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let observer = PublicationExternalFixture(); observer.available = false
            let coordinator = MediaInvalidationCoordinator(store: reopened, identity: f.identity,
                ordering: ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run)),
                scopes: RenditionScopeRegistry(leases: RenditionReadLeases(store: reopened)), external: observer)
            #expect(await coordinator.restore() == .unknown)
            #expect(try await mediaSnapshot(reopened).outbox.isEmpty)
            observer.available = true
            guard case .succeeded(let values) = await coordinator.restore() else { Issue.record("Reservation did not resume"); return }
            #expect(values.count == 1 && values.first?.record == f.invalidation)
        }
    }

    @Test func realAVPlayerTokenRequiresSeparateExplicitAction() async throws {
        try await withStorageRun { run in
            let movie = run.url.appendingPathComponent("s27.mov")
            try await SyntheticMovieFixture.write(to: movie, withAudio: true, durationSeconds: 8)
            let bytes = try Data(contentsOf: movie)
            let f = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let identity = try await establishRegistrationIdentity(f.store)
            let complete = try await f.complete(bytes)
            let player = try await AVRenditionPlayback.open(leases: f.leases, temporary: f.temporary, scope: f.scope) { _ in throw BackendContractError.notOnWiFi }
            let session = PlaybackSessionID(rawValue: "s27-real-playback")
            let play = Task { await player.play(.init(source: .local(complete, f.command.distribution), session: session, invalidationGeneration: .init(rawValue: 0))) }
            #expect(await renditionEventually { player.elapsedSeconds > 0.1 && player.decodedFrames > 0 })
            await player.end(session)
            guard case .succeeded(let token) = await play.value else { Issue.record("No real playback token"); return }
            #expect(try await mediaSnapshot(f.store).confirmations.isEmpty)
            let coordinator = MediaConfirmationCoordinator(store: f.store, identity: identity)
            let action = MediaOperationID(rawValue: "explicit-after-playing")
            let confirmed = await coordinator.confirm(token, action: action)
            guard case .succeeded(let record) = confirmed else { Issue.record("Explicit confirmation failed"); return }
            #expect(await coordinator.confirm(token, action: action) == confirmed)
            #expect(try await mediaSnapshot(f.store).confirmations == [record])
            #expect(await f.temporary.releaseUsage(complete.usage) == .succeeded(complete.id))
            _ = try await f.scope.close()
        }
    }
}

@MainActor private final class PublicationHeldOwner {
    let lease: MediaReadLease
    let leases: RenditionReadLeases
    var stopRequested = false
    var completed = false
    var callback: CheckedContinuation<Void, Never>?
    init(lease: MediaReadLease, leases: RenditionReadLeases) { self.lease = lease; self.leases = leases }
    func finishCallback() { completed = true; callback?.resume(); callback = nil }
    func stop() async throws -> RenditionReadTerminal {
        stopRequested = true
        if !completed { await withCheckedContinuation { callback = $0 } }
        try await leases.release(lease)
        return .init(epoch: lease.epoch, started: 1, completed: 1, bytes: 0, handlesClosed: true)
    }
}
