import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct RenditionPlaybackModelTests {
    @Test func noProgressCannotConfirmAndNaturalEndRetainsOnlyTheCurrentPresentationToken() async throws {
        let f = try await ProductRenditionFixture.make(duration: 1.2)
        let model = RenditionPlaybackModel(factory: f.factory())
        #expect(!model.canConfirm && model.token == nil)
        await model.confirm()
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
        #expect(model.open(f.target))
        #expect(await renditionEventually { model.playback?.phase == .ended && model.token != nil })
        let token = try #require(model.token)
        #expect(model.canConfirm && model.playback?.sdkDetached == true)
        await model.confirm()
        #expect(model.confirmation?.intent.playback == token && !model.canConfirm)
        await model.close()
        #expect(model.token == nil && model.target == nil && model.session == nil && !model.canConfirm)
        #expect(try await mediaSnapshot(f.services.store).confirmations.count == 1)
    }

    @Test func oldPresentationClosureCannotCloseOrConfirmTheNewSession() async throws {
        let f = try await ProductRenditionFixture.make()
        let next = try await ProductRenditionFixture.seed(services: f.services, libraryFactory: f.libraryFactory,
            capture: "next-session-" + UUID().uuidString.lowercased(), local: false)
        let model = RenditionPlaybackModel(factory: f.factory())
        #expect(model.open(f.target))
        #expect(await renditionEventually { model.token != nil })
        let oldSession = model.session
        await model.close()
        #expect(model.open(next.target))
        #expect(model.token == nil && !model.canConfirm && model.session != oldSession)
        await model.close(ifSession: oldSession)
        #expect(model.target == next.target)
        #expect(await renditionEventually { model.token != nil })
        #expect(model.token?.distribution == next.distribution)
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
        await model.close()
    }

    @Test func delayedOldStopJoinsOnlyItsCapturedTaskAndCannotWaitForTheNewPresentation() async throws {
        let f = try await ProductRenditionFixture.make()
        let next = try await ProductRenditionFixture.seed(services: f.services, libraryFactory: f.libraryFactory,
            capture: "stop-join-next-" + UUID().uuidString.lowercased(), local: false)
        let probe = ProductStopJoinProbe()
        let model = RenditionPlaybackModel(factory: f.factory(), stopJoinBoundary: { await probe.afterPlayerEnd() },
            didChange: { await probe.changed() })
        #expect(model.open(f.target))
        #expect(await renditionEventually { model.token != nil })
        let oldSession = model.session
        let oldStop = Task { await model.stop(); probe.oldStopFinished = true }
        defer { probe.releaseStop(); probe.releaseChanges() }
        #expect(await renditionEventually { probe.stopArrived })
        await model.close() // A second stop joins A while the first A.stop is held.
        probe.holdChanges = true
        #expect(model.open(next.target))
        #expect(await renditionEventually { probe.changeArrived && model.token != nil })
        // B's real start task is still suspended in its refresh notification.
        // The old stop must return without joining B or publishing state to it.
        probe.releaseStop()
        #expect(await renditionEventually { probe.oldStopFinished })
        #expect(model.session != oldSession && model.target == next.target)
        #expect(model.token?.distribution == next.distribution)
        probe.releaseChanges()
        await oldStop.value
        await model.close()
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
    }

    @Test func uncertainConfirmationReusesTheExactPlayedTokenAndActionAfterStop() async throws {
        let f = try await ProductRenditionFixture.make()
        let factory = f.factory()
        let boundary = ProductConfirmationLostReply(factory: factory)
        let model = RenditionPlaybackModel(factory: factory, confirm: { token, action, identity in
            await boundary.confirm(token, action: action, identity: identity)
        })
        #expect(model.open(f.target))
        #expect(await renditionEventually { model.token != nil })
        await model.stop()
        let token = try #require(model.token)
        await model.confirm()
        #expect(model.confirmationUnknown && model.confirmation == nil && model.canConfirm)
        let first = try #require(await boundary.calls.first)
        await model.confirm()
        let calls = await boundary.calls
        #expect(calls.count == 2)
        #expect(PublicationStoreBoundary.exact(calls[0].token, token)
            && PublicationStoreBoundary.exact(calls[1].token, token)
            && PublicationStoreBoundary.exact(calls[0].action, calls[1].action))
        #expect(model.confirmation?.intent.operation == first.action && !model.confirmationUnknown)
        #expect(try await mediaSnapshot(f.services.store).confirmations.count == 1)
        await model.close()
    }

    @Test func registrationChangeAfterActualProgressRejectsConfirmationWithoutLosingTheOriginal() async throws {
        let f = try await ProductRenditionFixture.make()
        let model = RenditionPlaybackModel(factory: f.factory())
        #expect(model.open(f.target))
        #expect(await renditionEventually { model.token != nil })
        await model.stop()
        _ = try await mediaRegister(f.services.store, registration: .init(destination: f.registration.destination,
            id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
        await model.confirm()
        #expect(model.confirmationFailed && model.confirmation == nil)
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
        await model.close()
    }

    @Test func delayedOriginalHandoffReservesAllLocalAndRemoteRenditionEntrancesBeforeAwait() async throws {
        let f = try await ProductRenditionFixture.make(local: true)
        let original = OriginalPlaybackModel(playback: AVOriginalPlayback(access: f.services.access))
        let model = RenditionPlaybackModel(factory: f.factory())
        let delayed = ProductDelayedOriginalCommands(base: OriginalPlaybackLibraryCommands(model: original))
        let commands = RenditionPlaybackLibraryCommands(base: delayed, original: original, rendition: model)
        let target = LibraryCommandTarget(capture: f.original.capture, reference: try #require(f.localReference), original: f.original)
        func request(_ action: LibraryAction) -> LibraryCommandRequest {
            .init(id: .init(rawValue: UUID().uuidString), action: action, targets: [target], displayedRevision: 0,
                discardRiskAcknowledged: false)
        }
        let first = Task { await commands.submit(request(.playOriginal)) }
        #expect(await renditionEventually { delayed.arrived })
        guard case .rejected = await commands.submit(request(.playRendition)) else {
            delayed.release(); _ = await first.value; Issue.record("Local rendition crossed original handoff reservation"); return
        }
        guard case .rejected = await commands.play(original: f.original, destination: f.registration.destination,
            operation: .init(rawValue: UUID().uuidString)) else {
            delayed.release(); _ = await first.value; Issue.record("Remote row crossed original handoff reservation"); return
        }
        guard case .rejected = await commands.submit(request(.playOriginal)) else {
            delayed.release(); _ = await first.value; Issue.record("Second original crossed reservation"); return
        }
        #expect(model.target == nil && delayed.calls == 1)
        delayed.release()
        #expect(await first.value == .accepted)
        #expect(original.target != nil)
        await original.close()
        #expect(await commands.submit(request(.playRendition)) == .accepted)
        guard case .rejected = await commands.submit(request(.playOriginal)) else {
            await model.close(); Issue.record("Original crossed live rendition target"); return
        }
        #expect(await renditionEventually { model.token != nil })
        await model.close()
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
    }

    @Test func immediateCloseAndBackgroundStopJoinPreparationAndNeverConfirmAutomatically() async throws {
        let f = try await ProductRenditionFixture.make()
        let composition = ProductComposition(factory: f.libraryFactory)
        await composition.open()
        let library = try #require(composition.library), model = try #require(composition.renditionPlayback)
        let row = try #require(library.snapshot?.remoteItems.first)
        await library.playRemoteRendition(row)
        await composition.enteredBackground()
        #expect(!model.isBusy && model.playback?.player == nil)
        #expect(model.playback?.startedMonitors == model.playback?.completedMonitors)
        #expect(try await mediaSnapshot(f.services.store).confirmations.isEmpty)
        await model.close()
        #expect(model.token == nil && model.target == nil)
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
    }
}

actor ProductConfirmationLostReply {
    struct Call: Sendable { let token: PlaybackToken; let action: MediaOperationID }
    let factory: ProductRenditionFactory
    private(set) var calls: [Call] = []
    init(factory: ProductRenditionFactory) { self.factory = factory }
    func confirm(_ token: PlaybackToken, action: MediaOperationID,
                 identity: RegistrationStoreIdentity) async -> BackendOutcome<ConfirmationRecord> {
        calls.append(.init(token: token, action: action))
        let result = await factory.confirm(token, action: action, identity: identity)
        return calls.count == 1 ? .unknown : result
    }
}

@MainActor final class ProductDelayedOriginalCommands {
    let base: any LibraryCommandPort
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var arrived = false
    private(set) var calls = 0
    init(base: any LibraryCommandPort) { self.base = base }
    func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability { base.availability(action, items: items) }
    func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse {
        calls += 1; arrived = true
        await withCheckedContinuation { continuation = $0 }
        return await base.submit(request)
    }
    func release() { continuation?.resume(); continuation = nil }
}
extension ProductDelayedOriginalCommands: LibraryCommandPort {}

@MainActor final class ProductStopJoinProbe {
    var holdChanges = false
    var oldStopFinished = false
    private(set) var stopArrived = false
    private(set) var changeArrived = false
    private var stops = 0
    private var stopWaiter: CheckedContinuation<Void, Never>?
    private var changeWaiter: CheckedContinuation<Void, Never>?
    func afterPlayerEnd() async {
        stops += 1
        if stops == 1 {
            stopArrived = true
            await withCheckedContinuation { stopWaiter = $0 }
        }
    }
    func changed() async {
        if holdChanges {
            changeArrived = true
            await withCheckedContinuation { changeWaiter = $0 }
        }
    }
    func releaseStop() { stopWaiter?.resume(); stopWaiter = nil }
    func releaseChanges() { holdChanges = false; changeWaiter?.resume(); changeWaiter = nil }
}
