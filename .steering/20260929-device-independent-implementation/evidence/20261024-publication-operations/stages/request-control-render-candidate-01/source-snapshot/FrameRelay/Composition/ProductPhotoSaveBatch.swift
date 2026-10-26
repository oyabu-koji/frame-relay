import Foundation

/// Uses the playback factory's exact same owner and scope registry. No remote
/// request, synthetic original reference or alternate temporary root exists.
actor ProductPhotoSaveBatch: PhotoSaveBatchExecutionPort {
    private let services: ProductLibraryServices
    private let factory: ProductRenditionFactory
    private let capture: CaptureMediaAdmission

    init(services: ProductLibraryServices, factory: ProductRenditionFactory, capture: CaptureMediaAdmission) {
        self.services = services; self.factory = factory; self.capture = capture
    }

    func source(for target: LibraryRenditionTarget) async throws -> PhotoSaveSource {
        try await factory.photoSource(target)
    }

    func reconcileKnownNonStarted(_ target: PhotoSaveBatchTarget) async {
        guard case .loaded(let snapshot) = await services.store.load(), snapshot.storeIdentity == target.source.storeIdentity,
              let record = snapshot.photoRegistrations.first(where: {
                  PhotoSaveBatchValueValidation.exact($0.registration.intent.operation, target.operation)
              }), target.source.matches(record.registration), record.outcome == nil else { return }
        await factory.reconcileKnownPhotoSave(target.source)
    }

    func prepare(_ target: PhotoSaveBatchTarget) async throws -> any PreparedPhotoSavePort {
        try target.validate()
        guard case .loaded(let snapshot) = await services.store.load(), snapshot.storeIdentity == target.source.storeIdentity else {
            throw BackendContractError.identityMismatch
        }
        let latest = snapshot.photoRegistrations.last { PhotoSaveBatchValueValidation.exact($0.registration.intent.key, target.key) }
        if let previous = target.retryOf {
            guard let latest, latest.outcome?.permitsExplicitRetry == true,
                  PhotoSaveBatchValueValidation.exact(latest.registration.intent.operation, previous),
                  Self.matches(latest.registration, source: target.source) else { throw BackendContractError.ineligibleOriginal }
            let owner = try await factory.photoOwner(target.source)
            let coordinator = await factory.photoCoordinator(owner: owner, identity: target.source.storeIdentity)
            return ProductPreparedPhotoSource(store: services.store, factory: factory, capture: capture,
                target: target, source: nil, coordinator: coordinator, previous: latest.registration.intent)
        }
        guard latest == nil else { throw BackendContractError.ineligibleOriginal }
        let source = try await factory.preparePhoto(target.source)
        let coordinator = await factory.photoCoordinator(owner: source.owner, identity: target.source.storeIdentity)
        return ProductPreparedPhotoSource(store: services.store, factory: factory, capture: capture,
            target: target, source: source, coordinator: coordinator, previous: nil)
    }

    nonisolated static func matches(_ registration: CommittedPhotoRegistrationIntent, source: PhotoSaveSource) -> Bool {
        source.matches(registration)
    }
}

/// Single-use live capability. Its state changes before the first suspension;
/// cancel/release cannot race an SDK request or release an unknown photo owner.
actor ProductPreparedPhotoSource: PreparedPhotoSavePort, PhotoSavePendingCancellationPort {
    private enum State {
        case prepared
        case performing(CommittedPhotoSaveBatchChild, Task<BackendOutcome<PhotoRegistrationRecord>, Never>, PhotoSaveDispatchClaim)
        case ownershipUnknown
        case releasing(Task<Bool, Never>)
        case released
    }
    private let store: any MediaOperationStorePort
    private let factory: ProductRenditionFactory
    private let capture: CaptureMediaAdmission
    private let target: PhotoSaveBatchTarget
    private let source: ProductRenditionSource?
    private let coordinator: PhotoSaveCoordinator
    private let previous: PhotoRegistrationIntent?
    private var state: State = .prepared

    init(store: any MediaOperationStorePort, factory: ProductRenditionFactory, capture: CaptureMediaAdmission,
         target: PhotoSaveBatchTarget, source: ProductRenditionSource?, coordinator: PhotoSaveCoordinator,
         previous: PhotoRegistrationIntent?) {
        self.store = store; self.factory = factory; self.capture = capture; self.target = target
        self.source = source; self.coordinator = coordinator; self.previous = previous
    }

    func perform(_ child: CommittedPhotoSaveBatchChild) async -> BackendOutcome<PhotoRegistrationRecord> {
        switch state {
        case .performing(let existing, let task, _):
            guard PhotoSaveBatchValueValidation.exact(existing.mutation, child.mutation),
                  PhotoSaveBatchValueValidation.exact(existing.commit, child.commit) else { return .failed(.rejected) }
            return await task.value
        case .ownershipUnknown: return .unknown
        case .releasing, .released: return .notExecuted
        case .prepared: break
        }
        guard child.isCommitted, PhotoSaveBatchValueValidation.exact(child.target, target),
              child.expectedStoreIdentity == target.source.storeIdentity else { return .failed(.rejected) }
        guard !capture.snapshot().isHeld else { return .inProgress }
        let claim: PhotoSaveDispatchClaim?
        if let previous { claim = coordinator.reserveRetry(previous, action: target.operation) }
        else if let source { claim = coordinator.reserveSave(source.receipt, action: target.operation) }
        else { claim = nil }
        guard let claim else {
            // Another coordinator may own this exact operation/use. It is not
            // evidence of non-start and cannot permit this capability to release.
            state = .ownershipUnknown
            return .unknown
        }
        let task = Task { await self.performOnce(child) }
        state = .performing(child, task, claim)
        return await task.value
    }

    func releaseIfNotStarted() async -> Bool {
        switch state {
        case .performing, .ownershipUnknown: return false
        case .released: return true
        case .releasing(let task): return await task.value
        case .prepared:
            let task = Task { [factory, source] in
                if let source { return await factory.release(source) }
                // A retry has not yet acquired its fresh use.
                return true
            }
            state = .releasing(task)
            let released = await task.value
            if released { state = .released }
            return released
        }
    }

    func cancelBeforeSDKStart() async {
        guard case .performing(let child, _, let claim) = state,
              PhotoSaveBatchValueValidation.exact(child.target, target) else { return }
        // The coordinator's shared latch decides whether this exact live add
        // was accepted. Never release a performing use from this capability.
        _ = claim.cancelBeforeStart()
    }

    func stopForCapture() async -> Bool {
        switch state {
        case .prepared, .releasing, .released:
            return await releaseIfNotStarted()
        case .ownershipUnknown: return false
        case .performing(_, let task, let claim):
            _ = claim.cancelBeforeStart()
            _ = await task.value
            return await coordinator.waitForCaptureLocalStop()
        }
    }

    private func performOnce(_ child: CommittedPhotoSaveBatchChild) async -> BackendOutcome<PhotoRegistrationRecord> {
        guard case .committed(let receipt) = await store.lookupCommit(child.mutation), receipt == child.commit,
              case .loaded(let snapshot) = await store.load(), snapshot.storeIdentity == target.source.storeIdentity,
              let stored = snapshot.photoSaveBatches.first(where: { PhotoSaveBatchValueValidation.exact($0.batch.operation, child.batch) })?
                .targets.first(where: { PhotoSaveBatchValueValidation.exact($0.target, target) }),
              case .starting(let begun) = stored.status,
              PhotoSaveBatchValueValidation.exact(begun.mutation, child.mutation),
              PhotoSaveBatchValueValidation.exact(begun.commit, child.commit), stored.registration == nil else { return .unknown }
        do {
            let current = try await factory.photoSource(.init(original: target.source.rendition.original,
                destination: target.source.registration.destination))
            guard PhotoSaveBatchValueValidation.exact(current, target.source) else {
                await releaseDefiniteNonStart(); return .notExecuted
            }
        } catch { await releaseDefiniteNonStart(); return .notExecuted }
        if let previous {
            return await coordinator.retry(previous, action: target.operation)
        }
        guard let source else { return .failed(.rejected) }
        let outcome = await coordinator.save(source.receipt, action: target.operation)
        // A definite rejection before an intent was accepted owns no SDK use.
        // Unknown outcomes remain under PhotoSaveCoordinator's provenance.
        if case .failed = outcome { await releaseDefiniteNonStart() }
        return outcome
    }

    private func releaseDefiniteNonStart() async {
        if let source { _ = await factory.release(source) }
    }
}
