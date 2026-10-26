import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized)
struct ProductBackgroundCompositionTests {
    @MainActor @Test func completionRunsOnMainActorOncePerDrainedBatchIncludingLateHandler() async throws {
        let identity = backgroundCompositionSession()
        let restorer = BackgroundRouterRestorationProbe()
        let router = ProductBackgroundEventRouter { identifier, observer in
            await restorer.restore(identifier, observer: observer)
        }
        let completion = BackgroundCompletionProbe()
        let first = BackgroundMediaDrainObservation(session: identity, stream: UUID(), sequence: 4)
        // didFinishEvents may be observed before UIKit delivers its handler.
        await restorer.finish(first)
        router.handleEvents(identifier: identity.identifier.rawValue) {
            MainActor.preconditionIsolated()
            completion.complete()
        }
        try await backgroundEventually { await completion.count == 1 }
        #expect(router.pendingHandlerCount == 0)
        await restorer.finish(first)
        #expect(completion.count == 1)
        router.handleEvents(identifier: identity.identifier.rawValue) {
            MainActor.preconditionIsolated()
            completion.complete()
        }
        #expect(completion.count == 1 && router.pendingHandlerCount == 1)
        let second = BackgroundMediaDrainObservation(session: identity, stream: first.stream, sequence: 9)
        await restorer.finish(second)
        #expect(completion.count == 2 && router.pendingHandlerCount == 0)
        await restorer.finish(second)
        #expect(completion.count == 2)
    }

    @MainActor @Test func openingDelayAndUnknownSessionKeepCompletionPending() async throws {
        let opening = BackgroundCheckpoint()
        let restorer = BackgroundRouterRestorationProbe(opening: opening)
        let identity = backgroundCompositionSession()
        let router = ProductBackgroundEventRouter { identifier, observer in
            await restorer.restore(identifier, observer: observer)
        }
        let completion = BackgroundCompletionProbe()
        router.handleEvents(identifier: identity.identifier.rawValue) { completion.complete() }
        try await opening.waitForArrival()
        await restorer.finish(.init(session: identity, stream: UUID(), sequence: 1))
        #expect(completion.count == 0 && router.pendingHandlerCount == 1)
        await opening.release()
        try await backgroundEventually { await completion.count == 1 }
        router.handleEvents(identifier: "unknown.session") { completion.complete() }
        try await backgroundEventually { await restorer.callCount() >= 2 }
        #expect(completion.count == 1 && router.pendingHandlerCount == 1)
    }

    @MainActor @Test func handlerOpensSameProductWriterWithoutAnyUIAppearanceAndUnknownFactoryCalls() async throws {
        let parent = try backgroundCompositionParent()
        let library = ProductLibraryFactory(supportDirectory: parent)
        let counts = BackgroundFactoryProbe()
        let opening = BackgroundLibraryOpenProbe()
        let background = ProductBackgroundMediaFactory(library: library,
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { _ in await counts.sourceCreated(); throw BackendContractError.unavailable },
            openLibrary: {
                let services = try await library.open()
                await opening.didOpen(services)
                return services
            })
        let router = ProductBackgroundEventRouter { identifier, observer in
            await background.restore(identifier: identifier, didDrain: observer)
        }
        let completion = BackgroundCompletionProbe()
        router.handleEvents(identifier: "unknown.FrameRelay.background") { completion.complete() }
        try await backgroundEventually { await opening.count() > 0 }
        #expect(completion.count == 0 && router.pendingHandlerCount == 1)
        let services = try await library.open()
        #expect(await opening.sameWriter(services))
        #expect(FileManager.default.fileExists(atPath: services.run.url.appendingPathComponent("recordings.sqlite").path))
        #expect(await counts.counts() == [0, 0])
        #expect(await background.prepare() == .prepared(knownSessions: 0))
        let composition = ProductComposition(factory: library, backgroundFactory: background)
        await composition.open()
        #expect(composition.library != nil && composition.openingIssue == nil)
        #expect(await opening.sameWriter(try await library.open()))
        #expect(await counts.counts() == [0, 0])
    }

    @MainActor @Test func separateCompositionRootsDoNotBindToFirstGlobalBackgroundStore() async throws {
        let firstLibrary = ProductLibraryFactory(supportDirectory: try backgroundCompositionParent())
        let secondLibrary = ProductLibraryFactory(supportDirectory: try backgroundCompositionParent())
        let first = ProductComposition(factory: firstLibrary)
        let second = ProductComposition(factory: secondLibrary)
        await first.open()
        await second.open()
        #expect(first.library != nil && second.library != nil)
        #expect(first.openingIssue == nil && second.openingIssue == nil)
        let firstServices = try await firstLibrary.open()
        let secondServices = try await secondLibrary.open()
        #expect(firstServices.store !== secondServices.store)
        #expect(firstServices.run.url != secondServices.run.url)
        await first.enteredBackground()
        await second.enteredBackground()
        #expect(first.library?.snapshot?.items.isEmpty == true)
        #expect(second.library?.snapshot?.items.isEmpty == true)
    }

    @MainActor @Test func storeOpenFailureKeepsOSHandlerAndDoesNotInstantiateSDKOrSource() async throws {
        let counts = BackgroundFactoryProbe()
        let opened = BackgroundOpenFailureProbe()
        let background = ProductBackgroundMediaFactory(
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { _ in await counts.sourceCreated(); throw BackendContractError.unavailable },
            openLibrary: { await opened.attempt(); throw BackendContractError.unavailable })
        let router = ProductBackgroundEventRouter { identifier, observer in
            await background.restore(identifier: identifier, didDrain: observer)
        }
        let completion = BackgroundCompletionProbe()
        router.handleEvents(identifier: "known.only.in.unavailable.store") { completion.complete() }
        try await backgroundEventually { await opened.count() == 1 }
        #expect(completion.count == 0 && router.pendingHandlerCount == 1)
        #expect(await background.prepare() == .held)
        #expect(await counts.counts() == [0, 0])
    }

    @MainActor @Test func knownSessionIsReusedAcrossPreparationAndBackgroundHandlerWithoutAdoptingOldSource() async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundCompositionParent())
        let services = try await library.open()
        let originals = OriginalRemovalFixture(run: services.run, store: services.store, files: services.originals,
            access: services.access)
        let fixture = try await BackgroundCoordinatorFixture.make(originals)
        let source = try ManagedUploadSource(run: services.run, originals: services.access)
        let initialSDK = BackgroundSessionProbe(identity: fixture.plan.session)
        let creator = fixture.coordinator(sdk: initialSDK, source: source)
        guard case .started(let started) = await creator.startUpload(fixture.plan), let binding = started.binding,
              case .upload(_, let lease, let sourceIdentity) = started.intent.source else {
            Issue.record("Test-only creator did not establish a durable exact binding"); return
        }
        let observed = try #require(await initialSDK.observations().first)
        await initialSDK.finishStream()
        let recoveredSDK = BackgroundSessionProbe(identity: fixture.plan.session)
        await recoveredSDK.setObservations([observed])
        let factories = BackgroundFactoryProbe()
        let background = ProductBackgroundMediaFactory(library: library,
            sessionFactory: { identity in
                #expect(identity == fixture.plan.session)
                await factories.sdkCreated()
                return recoveredSDK
            }, sourceFactory: { _ in await factories.sourceCreated(); throw BackendContractError.unavailable })
        #expect(await background.prepare() == .prepared(knownSessions: 1))
        async let first = background.restore(identifier: fixture.plan.session.identifier.rawValue)
        async let second = background.restore(identifier: fixture.plan.session.identifier.rawValue)
        let restored = await (first, second)
        #expect(restored.0 && restored.1)
        #expect(await factories.counts() == [1, 0])
        let router = ProductBackgroundEventRouter { identifier, observer in
            await background.restore(identifier: identifier, didDrain: observer)
        }
        let completion = BackgroundCompletionProbe()
        router.handleEvents(identifier: fixture.plan.session.identifier.rawValue) { completion.complete() }
        await recoveredSDK.completeUnknown(observed, outcome: .cancelled, finishEvents: true)
        try await backgroundEventually { await completion.count == 1 }
        let durable = try await mediaSnapshot(services.store).backgroundTasks[0]
        #expect(durable.terminal?.binding == binding && durable.ownerClosure == nil)
        #expect((await source.resources()).openHandles == 1)
        #expect(try await mediaOriginalSnapshot(services.store).logicalOriginals[0].readers == [lease])
        #expect(await factories.counts() == [1, 0])
        await recoveredSDK.finishStream()
        _ = try await source.finish(sourceIdentity, lease: lease,
            terminal: .init(binding: binding, outcome: .cancelled))
        _ = await services.access.releaseRead(lease)
        _ = try await source.closeOwner()
    }
}

actor BackgroundRouterRestorationProbe {
    private let opening: BackgroundCheckpoint?
    private var observer: BackgroundMediaCoordinator.DidDrain?
    private var ready = false
    private var finished: [BackgroundMediaDrainObservation] = []
    private var calls = 0
    init(opening: BackgroundCheckpoint? = nil) { self.opening = opening }
    func restore(_ identifier: String, observer: @escaping BackgroundMediaCoordinator.DidDrain) async -> Bool {
        calls += 1
        guard identifier != "unknown.session" else { return false }
        self.observer = observer
        await opening?.checkpoint()
        ready = true
        for observation in finished { await observer(observation) }
        return true
    }
    func finish(_ observation: BackgroundMediaDrainObservation) async {
        finished.append(observation)
        if ready { await observer?(observation) }
    }
    func callCount() -> Int { calls }
}

@MainActor final class BackgroundCompletionProbe {
    private(set) var count = 0
    func complete() { count += 1 }
}

actor BackgroundLibraryOpenProbe {
    private var services: ProductLibraryServices?
    private var opens = 0
    func didOpen(_ services: ProductLibraryServices) { self.services = services; opens += 1 }
    func count() -> Int { opens }
    func sameWriter(_ other: ProductLibraryServices) -> Bool { services?.store === other.store }
}

actor BackgroundOpenFailureProbe {
    private var attempts = 0
    func attempt() { attempts += 1 }
    func count() -> Int { attempts }
}

nonisolated private func backgroundCompositionParent() throws -> URL {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-background-composition-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

nonisolated private func backgroundCompositionSession() -> BackgroundMediaSessionIdentity {
    .init(identifier: .init(rawValue: "test.FrameRelay.router." + UUID().uuidString), generation: .init(rawValue: UUID()))
}
