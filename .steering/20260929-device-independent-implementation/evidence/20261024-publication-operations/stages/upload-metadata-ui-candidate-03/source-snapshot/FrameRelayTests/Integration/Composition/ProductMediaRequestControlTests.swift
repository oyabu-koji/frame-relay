import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct ProductMediaRequestControlTests {
    @Test func queuedPersonIntentAndReopenedLookupNeverCreateSDKSourceOrClearCaptureWaits() async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let counts = BackgroundFactoryProbe()
        let factory = ProductBackgroundMediaFactory(library: library,
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { _ in await counts.sourceCreated(); throw BackendContractError.unavailable })
        let request = try #require(try await mediaSnapshot(services.store).requests.first)
        let pause = try personProductPlan([request], identity: seed.fixture.plan.context.storeIdentity, action: .pause)
        let saved = try personRecorded(await factory.submitPersonControl(pause))
        #expect(saved.children[0].decision == .recorded)
        let owner = CaptureMediaOwner(context: try CaptureFixture(clip: UUID().uuidString).context, visit: UUID(), nonce: UUID())
        factory.captureAdmission.begin(owner, phases: [.recording])
        await factory.synchronizeCapture()
        let resume = try personProductPlan([request], identity: pause.storeIdentity, action: .resumeIntent)
        let resumed = try personRecorded(await factory.submitPersonControl(resume))
        #expect(resumed.children[0].decision == .recorded)
        #expect(try await mediaSnapshot(services.store).requests[0].intent == .running)
        #expect(try await mediaSnapshot(services.store).requests[0].waits.contains(.recording))
        let cancel = try personProductPlan([request], identity: pause.storeIdentity, action: .cancel)
        _ = try personRecorded(await factory.submitPersonControl(cancel))
        factory.captureAdmission.end(owner)
        await factory.synchronizeCapture()
        let forbidden = try personRecorded(await factory.submitPersonControl(personProductPlan([request], identity: pause.storeIdentity, action: .resumeIntent)))
        #expect(forbidden.children[0].decision == .notProcessed(.cancelled))
        let before = try await mediaSnapshot(services.store)
        let fresh = ProductBackgroundMediaFactory(library: library,
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { _ in await counts.sourceCreated(); throw BackendContractError.unavailable })
        guard case .recorded(let replay, let stops) = await fresh.lookupPersonControl(pause) else { throw BackendContractError.unknownResult }
        #expect(replay == saved && stops[0].disposition == .notRequested)
        #expect(await counts.counts() == [0, 0])
        #expect(try await mediaSnapshot(services.store) == before)
        #expect(before.requests[0].intent == .cancelled && before.backgroundTasks.isEmpty)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting)
        #expect(try await mediaSnapshot(reopened).personControls == before.personControls)
        let digest = try await services.originals.digest(for: seed.binding.reference)
        #expect(digest.sha256 == seed.binding.original.content.digest)
    }

    @Test(arguments: ["before", "after"])
    func wholeUnknownRetainsTheOriginalMutationAndLookupCannotRebaseOrDispatchAgain(point: String) async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let store = PersonControlTestStore(base: services.store, loss: point)
        let counts = BackgroundFactoryProbe()
        let owner = BackgroundMediaCoordinator(store: store, identity: seed.fixture.plan.context.storeIdentity, originals: services.access,
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { await counts.sourceCreated(); throw BackendContractError.unavailable })
        let request = try #require(try await mediaSnapshot(services.store).requests.first)
        let plan = try personProductPlan([request], identity: seed.fixture.plan.context.storeIdentity, action: .pause)
        #expect(await owner.submitPersonControl(plan) == .unknown)
        #expect(await owner.submitPersonControl(plan) == .unknown)
        let changed = try MediaPersonControlPlan(parent: plan.parent, storeIdentity: plan.storeIdentity, scope: .single,
            action: .cancel, children: plan.children)
        #expect(await owner.lookupPersonControl(changed) == .rejected(.identityMismatch))
        let original = try #require(await store.personMutations().first)
        #expect(await store.personMutations().count == 1)
        let replacement = BackgroundMediaCoordinator(store: store, identity: plan.storeIdentity, originals: services.access,
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { await counts.sourceCreated(); throw BackendContractError.unavailable })
        #expect(await replacement.lookupPersonControl(plan) == .unknown)
        try await store.materializeOriginal()
        let later = try await personProductQueuedRequest(services, original: seed.binding.original, registration: seed.record.registration)
        #expect(await owner.lookupPersonControl(plan) == .unknown)
        await store.reveal()
        let saved = try personRecorded(await owner.lookupPersonControl(plan))
        #expect(MediaPersonControlValueValidation.exact(saved.mutation, original))
        #expect(saved.plan.children == plan.children && saved.children[0].decision == .recorded)
        #expect(await store.personMutations().count == 1)
        #expect(try await mediaSnapshot(services.store).requests.first { $0.operation == later.operation }?.intent == .running)
        #expect(await counts.counts() == [0, 0])
        let before = try await mediaSnapshot(services.store)
        _ = try personRecorded(await owner.submitPersonControl(plan))
        #expect(try await mediaSnapshot(services.store) == before)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting)
        #expect(try await mediaSnapshot(reopened).personControls == [saved])
    }

    @Test func aDefiniteCASCompletionRaceReevaluatesOnlyTheSameFixedPlan() async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let request = try #require(try await mediaSnapshot(services.store).requests.first)
        let store = PersonControlTestStore(base: services.store, completionRace: request)
        let owner = BackgroundMediaCoordinator(store: store, identity: seed.fixture.plan.context.storeIdentity, originals: services.access,
            sessionFactory: { _ in throw BackendContractError.unavailable }, sourceFactory: { throw BackendContractError.unavailable })
        let plan = try personProductPlan([request], identity: seed.fixture.plan.context.storeIdentity, action: .pause)
        let record = try personRecorded(await owner.submitPersonControl(plan))
        #expect(record.children[0].decision == .notProcessed(.completed))
        let mutations = await store.personMutations()
        #expect(mutations.count == 2 && mutations[0].expectedRevision < mutations[1].expectedRevision)
        #expect(MediaPersonControlValueValidation.exact(mutations[0].change, mutations[1].change))
        #expect(try await mediaSnapshot(services.store).requests[0].intent == .running)
    }

    @Test func threeDefiniteCASConflictsRejectWithoutSDKWorkAndAllowANewParent() async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let before = try await mediaSnapshot(services.store)
        let request = try #require(before.requests.first)
        let counts = BackgroundFactoryProbe()
        let store = PersonControlTestStore(base: services.store, revisionConflicts: 3)
        let owner = BackgroundMediaCoordinator(store: store, identity: seed.fixture.plan.context.storeIdentity, originals: services.access,
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { await counts.sourceCreated(); throw BackendContractError.unavailable })
        let plan = try personProductPlan([request], identity: seed.fixture.plan.context.storeIdentity, action: .pause)
        #expect(await owner.submitPersonControl(plan) == .rejected(.revisionConflict))
        let conflicts = await store.personMutations()
        #expect(conflicts.count == 3)
        #expect(conflicts.allSatisfy { $0.expectedRevision == before.revision
            && MediaPersonControlValueValidation.exact($0.change, BackendStoreChange.personControl(plan)) })
        #expect(try await mediaSnapshot(services.store) == before)
        #expect(await counts.counts() == [0, 0])
        let next = try personProductPlan([request], identity: plan.storeIdentity, action: .pause)
        let record = try personRecorded(await owner.submitPersonControl(next))
        #expect(record.plan == next && record.children[0].decision == .recorded)
        #expect(try await mediaSnapshot(services.store).personControls == [record])
        #expect(await store.personMutations().count == 4)
        #expect(await counts.counts() == [0, 0])
    }

    @Test func aChangedStoreIdentityAfterCommitCannotDispatchOrBorrowTheCommittedReceipt() async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let counts = BackgroundFactoryProbe()
        let store = PersonControlTestStore(base: services.store, identityFaultAfterCommit: true)
        let owner = BackgroundMediaCoordinator(store: store, identity: seed.fixture.plan.context.storeIdentity, originals: services.access,
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { await counts.sourceCreated(); throw BackendContractError.unavailable })
        let request = try #require(try await mediaSnapshot(services.store).requests.first)
        let plan = try personProductPlan([request], identity: seed.fixture.plan.context.storeIdentity, action: .pause)
        #expect(await owner.submitPersonControl(plan) == .unknown)
        #expect(await owner.lookupPersonControl(plan) == .unknown)
        #expect(await counts.counts() == [0, 0])
        #expect(await store.personMutations().count == 1)
        await store.restoreObservedIdentity()
        let record = try personRecorded(await owner.lookupPersonControl(plan))
        let mutation = try #require(await store.personMutations().first)
        #expect(MediaPersonControlValueValidation.exact(record.mutation, mutation))
        #expect(await store.personMutations().count == 1)
        #expect(await counts.counts() == [0, 0])
    }

    @Test(arguments: ["cancel-unknown", "resume", "new-attempt"])
    func concurrentParentsFinishAnOldStopWithoutWeakeningCancelOrStoppingANewAttempt(mode: String) async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let managed = try ManagedUploadSource(run: services.run, originals: services.access)
        let source = BackgroundSourceProbe(base: managed), sdk = BackgroundSessionProbe(identity: seed.fixture.plan.session)
        let gate = BackgroundCheckpoint()
        let store = PersonControlTestStore(base: services.store, stopGate: gate, hideCancel: mode == "cancel-unknown")
        let owner = BackgroundMediaCoordinator(store: store, identity: seed.fixture.plan.context.storeIdentity, originals: services.access,
            admission: BackgroundPermitProbe(), sessionFactory: { _ in sdk }, sourceFactory: { source })
        guard case .started(let started) = await owner.startUpload(seed.fixture.plan), let binding = started.binding else { throw BackendContractError.notCommitted }
        let request = try #require(try await mediaSnapshot(services.store).requests.first)
        let pause = try personProductPlan([request], identity: seed.fixture.plan.context.storeIdentity, action: .pause)
        let pausing = Task { await owner.submitPersonControl(pause) }
        try await gate.waitForArrival()
        let replacementCalls = BackgroundFactoryProbe()
        let replacement = ProductBackgroundMediaFactory(library: library,
            sessionFactory: { _ in await replacementCalls.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { _ in await replacementCalls.sourceCreated(); throw BackendContractError.unavailable })
        guard case .recorded(_, let interrupted) = await replacement.lookupPersonControl(pause) else { throw BackendContractError.unknownResult }
        #expect(interrupted[0].disposition == .notRequested)
        #expect(await replacementCalls.counts() == [0, 0])
        let interruptedSDKCounts = await sdk.counts(), interruptedResources = await managed.resources()
        #expect(interruptedSDKCounts[2] == 0 && interruptedResources.openHandles == 1)
        let next = try personProductPlan([request], identity: pause.storeIdentity, action: mode == "cancel-unknown" ? .cancel : .resumeIntent)
        let nextResult = await owner.submitPersonControl(next)
        if mode == "cancel-unknown" { #expect(nextResult == .unknown) }
        else { #expect(try personRecorded(nextResult).children[0].decision == .recorded) }
        if mode == "new-attempt" {
            // A real probe terminal closes this exact actual source/FD/lease
            // before the next attempt is committed. No closure is synthesized.
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundInvalidationWaitForStopped(services.store, operation: request.operation)
            _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: request.operation, target: request.target, registration: request.registration,
                value: .reconciled(.init(context: .init(operation: request.operation, registration: request.registration,
                    target: request.target, session: seed.fixture.plan.macSession), observation: .init(rawValue: 2), result: .notExecuted))))
            _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: request.operation, target: request.target, registration: request.registration,
                value: .beginAttempt(.init(rawValue: UUID().uuidString))))
        }
        await gate.release()
        guard case .recorded(_, let stops) = await pausing.value else { throw BackendContractError.unknownResult }
        let current = try await mediaSnapshot(services.store)
        let sdkCounts = await sdk.counts()
        if mode == "new-attempt" {
            #expect(stops[0].disposition == .unknown && sdkCounts[2] == 0)
            #expect(current.requests[0].attempt != request.attempt && current.requests[0].transport == .active)
            #expect(current.requests[0].intent == .running)
        } else {
            #expect(stops[0].disposition == .requested && sdkCounts[2] == 1)
            #expect(current.requests[0].intent == (mode == "cancel-unknown" ? .cancelled : .running))
            #expect(current.requests[0].transport == .stopRequested)
            #expect((await managed.resources()).openHandles == 1)
            if mode == "cancel-unknown" {
                await store.reveal()
                _ = try personRecorded(await owner.lookupPersonControl(next))
                #expect((await sdk.counts())[2] == 1)
            }
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundInvalidationWaitForStopped(services.store, operation: request.operation)
        }
        #expect((await sdk.counts())[1] == 1) // Only the explicitly injected original start, no resumeIntent dispatch.
        #expect((await managed.resources()).openHandles == 0)
        #expect(await source.finishCount() == 1)
        let digest = try await services.originals.digest(for: seed.binding.reference)
        #expect(digest.sha256 == seed.binding.original.content.digest)
        await sdk.finishStream(); _ = try await managed.closeOwner()
    }

    @Test func factoryKeepsEachSDKStopIndependentAndDoesNotAdoptTheLiveOwnerAfterReopen() async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let secondRequest = try await personProductQueuedRequest(services, original: seed.binding.original, registration: seed.record.registration)
        let second = try await personProductUploadPlan(services, request: secondRequest)
        let firstSDK = BackgroundSessionProbe(identity: seed.fixture.plan.session), secondSDK = BackgroundSessionProbe(identity: second.session)
        let managed = try ManagedUploadSource(run: services.run, originals: services.access)
        let source = BackgroundSourceProbe(base: managed)
        let factory = ProductBackgroundMediaFactory(library: library, admission: BackgroundPermitProbe(), sessionFactory: { session in
            if session == second.session { return secondSDK }
            guard session == seed.fixture.plan.session else { throw BackendContractError.identityMismatch }
            return firstSDK
        }, sourceFactory: { _ in source })
        guard case .started(let firstState) = await factory.startUpload(seed.fixture.plan),
              case .started(let secondState) = await factory.startUpload(second),
              let firstBinding = firstState.binding, let secondBinding = secondState.binding else { throw BackendContractError.notCommitted }
        let observations = await firstSDK.observations()
        let foreign = BackgroundMediaTaskObservation(session: seed.fixture.plan.session, taskIdentifier: 999, taskDescription: "unknown", kind: .upload,
            state: .suspended, bytesSent: 0, bytesReceived: 0)
        await firstSDK.setObservations(observations + [foreign])
        let requests = try await mediaSnapshot(services.store).requests
        let plan = try personProductPlan(requests, identity: seed.fixture.plan.context.storeIdentity, action: .pause, scope: .allPause)
        guard case .recorded(let record, let stops) = await factory.submitPersonControl(plan) else { throw BackendContractError.notCommitted }
        #expect(record.children.map(\.decision) == [.recorded, .recorded])
        #expect(stops.map(\.disposition) == [.unknown, .requested])
        let firstCounts = await firstSDK.counts(), secondCounts = await secondSDK.counts()
        #expect(firstCounts[2] == 0 && secondCounts[2] == 1)
        _ = try personRecorded(await factory.submitPersonControl(plan))
        #expect(await firstSDK.counts() == firstCounts)
        #expect(await secondSDK.counts() == secondCounts)
        #expect((await managed.resources()).openHandles == 2)
        let counts = BackgroundFactoryProbe()
        let fresh = ProductBackgroundMediaFactory(library: library,
            sessionFactory: { _ in await counts.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { _ in await counts.sourceCreated(); throw BackendContractError.unavailable })
        guard case .recorded(let replay, let afterCrash) = await fresh.lookupPersonControl(plan) else { throw BackendContractError.unknownResult }
        #expect(replay == record && afterCrash.allSatisfy { $0.disposition == .notRequested })
        #expect(await counts.counts() == [0, 0])
        #expect((await managed.resources()).openHandles == 2)
        await firstSDK.setObservations(observations)
        await firstSDK.complete(firstBinding, outcome: .cancelled, finishEvents: true)
        await secondSDK.complete(secondBinding, outcome: .cancelled, finishEvents: true)
        try await backgroundInvalidationWaitForStopped(services.store, operation: seed.fixture.plan.context.operation)
        try await backgroundInvalidationWaitForStopped(services.store, operation: secondRequest.operation)
        #expect((await managed.resources()).openHandles == 0)
        #expect(try await mediaOriginalSnapshot(services.store).logicalOriginals.allSatisfy { $0.readers.isEmpty })
        #expect(try await mediaSnapshot(services.store).requests.allSatisfy { $0.intent == .paused })
        await firstSDK.finishStream(); await secondSDK.finishStream(); _ = try await managed.closeOwner()
    }
}

nonisolated func personProductPlan(_ requests: [MediaRequest], identity: RegistrationStoreIdentity,
    action: MediaPersonControlAction, scope: MediaPersonControlScope = .single) throws -> MediaPersonControlPlan {
    try .init(parent: .init(rawValue: UUID().uuidString), storeIdentity: identity, scope: scope, action: action,
        children: requests.map { .init(command: .init(rawValue: UUID().uuidString), target: .init($0)) })
}
nonisolated private func personRecorded(_ result: MediaPersonControlResult) throws -> StoredMediaPersonControlPlan {
    guard case .recorded(let record, _) = result else { throw BackendContractError.notCommitted }
    return record
}
@MainActor private func personProductQueuedRequest(_ services: ProductLibraryServices, original: OriginalContent,
    registration: RegistrationIdentity) async throws -> MediaRequest {
    let snapshot = try await mediaSnapshot(services.store)
    let request = MediaRequest(operation: .init(rawValue: UUID().uuidString), target: .original(original), purpose: .upload,
        registration: registration, expectedStartRevision: snapshot.revision)
    _ = try await mediaCommit(services.store, .request(command: request.operation, value: request))
    return try #require(try await mediaSnapshot(services.store).requests.last)
}
@MainActor private func personProductUploadPlan(_ services: ProductLibraryServices, request: MediaRequest) async throws -> BackgroundMediaUploadPlan {
    let session = UploadSessionID(rawValue: UUID().uuidString)
    _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: UUID().uuidString), operation: request.operation,
        target: request.target, registration: request.registration, value: .reconciled(.init(context: .init(operation: request.operation,
            registration: request.registration, target: request.target, session: session), observation: .init(rawValue: 1), result: .notExecuted))))
    var upload = URLRequest(url: try #require(URL(string: "https://example.invalid/person-control"))); upload.httpMethod = "PUT"
    return .init(id: .init(rawValue: UUID().uuidString), context: .init(operation: request.operation,
        attempt: .init(rawValue: UUID().uuidString), target: request.target, registration: request.registration, gateGeneration: 1,
        storeIdentity: try #require(try await mediaSnapshot(services.store).storeIdentity)),
        session: .init(identifier: .init(rawValue: "test.FrameRelay.person." + UUID().uuidString), generation: .init(rawValue: UUID())),
        taskDescription: UUID().uuidString, sourceID: .init(rawValue: UUID().uuidString), macSession: session, request: upload)
}

private actor PersonControlTestStore: MediaOperationStorePort {
    let base: any MediaOperationStorePort
    let loss: String?
    let stopGate: BackgroundCheckpoint?
    var completionRace: MediaRequest?
    var revisionConflicts: Int
    var hideCancel: Bool
    var hidden = true
    let identityFaultAfterCommit: Bool
    var wrongObservedIdentity = false
    var heldStop = false
    var seen: [BackendStoreMutation] = []
    init(base: any MediaOperationStorePort, loss: String? = nil, stopGate: BackgroundCheckpoint? = nil,
         hideCancel: Bool = false, completionRace: MediaRequest? = nil, identityFaultAfterCommit: Bool = false,
         revisionConflicts: Int = 0) {
        self.base = base; self.loss = loss; self.stopGate = stopGate; self.hideCancel = hideCancel; self.completionRace = completionRace
        self.identityFaultAfterCommit = identityFaultAfterCommit
        self.revisionConflicts = revisionConflicts
    }
    func load() async -> BackendStoreLoadResult {
        let actual = await base.load()
        guard wrongObservedIdentity, case .loaded(var snapshot) = actual else { return actual }
        snapshot.storeIdentity = .init(rawValue: UUID())
        return .loaded(snapshot) // Invalid observation only; the real store/UUID is never changed.
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .personControl = mutation.change {
            seen.append(mutation)
            if revisionConflicts > 0 {
                revisionConflicts -= 1
                return .rejected(.revisionConflict) // Definite non-commit at the controlled CAS boundary.
            }
            if let request = completionRace {
                completionRace = nil
                guard case .loaded(let snapshot) = await base.load() else { return .unknown }
                // Explicit external-result fixture input, not a native SDK terminal.
                let completed = BackendStoreChange.requestTransition(command: .init(rawValue: UUID().uuidString), operation: request.operation,
                    target: request.target, registration: request.registration, value: .reconciled(.init(context: .init(operation: request.operation,
                        registration: request.registration, target: request.target, session: request.session), observation: .init(rawValue: 2), result: .succeeded(.init(rawValue: "fixture-known-completion-race")))))
                guard case .committed = await base.commit(.init(expectedRevision: snapshot.revision, change: completed)) else { return .unknown }
                return .rejected(.revisionConflict)
            }
            if hidden && loss == "before" { return .unknown }
            let result = await base.commit(mutation)
            if identityFaultAfterCommit { wrongObservedIdentity = true }
            if hidden && loss == "after" { return .unknown }
            if hideCancel, case .personControl(let plan) = mutation.change, plan.action == .cancel { return .unknown }
            return result
        }
        let result = await base.commit(mutation)
        if case .backgroundTask(_, .stopRequested) = mutation.change, let stopGate, !heldStop {
            heldStop = true; await stopGate.checkpoint()
        }
        return result
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .personControl(let plan) = mutation.change,
           (hidden && loss != nil || hideCancel && plan.action == .cancel) { return .unknown }
        return await base.lookupCommit(mutation)
    }
    func materializeOriginal() async throws {
        let original = try #require(seen.first)
        guard case .committed = await base.commit(original) else { throw BackendContractError.notCommitted }
    }
    func reveal() { hidden = false; hideCancel = false }
    func restoreObservedIdentity() { wrongObservedIdentity = false }
    func personMutations() -> [BackendStoreMutation] { seen }
}
