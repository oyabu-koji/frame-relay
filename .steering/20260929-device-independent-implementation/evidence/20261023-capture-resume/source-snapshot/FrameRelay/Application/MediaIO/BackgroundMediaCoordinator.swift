import Foundation

nonisolated protocol BackgroundMediaUploadSourcePort: Sendable {
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) async throws -> BackgroundMediaUploadFile
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                for binding: BackgroundMediaTaskBinding) async throws
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                terminal: BackgroundMediaSDKTerminal) async throws -> BackgroundMediaOwnerClosure
}

extension ManagedUploadSource: BackgroundMediaUploadSourcePort {}

/// A planned attempt carries no positive network authority and owns no reader.
nonisolated struct BackgroundMediaUploadPlan: Sendable {
    let id: BackgroundMediaTaskID
    let context: BackgroundMediaRequestContext
    let session: BackgroundMediaSessionIdentity
    let taskDescription: String
    let sourceID: ManagedUploadSourceID
    let macSession: UploadSessionID
    let request: URLRequest
}

nonisolated enum BackgroundMediaStartRefusal: Equatable, Sendable {
    case strictAdmissionUnavailable, strictAdmissionRejected, identityMismatch
    case requestNotReady, downloadIngressUnavailable, sdkResumeUnavailable
    case captureBoundaryActive
    case removalBoundaryActive
}
nonisolated enum BackgroundMediaStartResult: Equatable, Sendable {
    case started(BackgroundMediaTaskState)
    /// Exact replay observes the same intent; it never copies/creates/resumes.
    case existing(BackgroundMediaTaskState)
    case refused(BackgroundMediaStartRefusal)
    case unknown
}

nonisolated struct UnavailableBackgroundMediaStrictAdmission: BackgroundMediaStrictAdmissionPort {
    func permit(_ context: BackgroundMediaRequestContext) async -> BackendOutcome<BackgroundMediaStrictPermit> { .notExecuted }
}

nonisolated enum BackgroundMediaControl: Equatable, Sendable {
    case pause, resume, cancel
    case wait(MediaWaitReason, active: Bool)
}

nonisolated struct BackgroundMediaDrainObservation: Hashable, Sendable {
    let session: BackgroundMediaSessionIdentity
    let stream: UUID
    let sequence: UInt64
}

private actor BackgroundMediaAttachmentBarrier {
    private var finished = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if finished { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func finish() {
        finished = true
        let continuations = waiting; waiting.removeAll()
        continuations.forEach { $0.resume() }
    }
}

/// One consumer per session awaits every disk/resource return. Delegate
/// callbacks never launch independent terminal/finish-event Tasks.
actor BackgroundMediaCoordinator: OriginalRemovalBackgroundPort {
    typealias SessionFactory = @Sendable (BackgroundMediaSessionIdentity) async throws -> any BackgroundMediaSessionPort
    typealias SourceFactory = @Sendable () async throws -> any BackgroundMediaUploadSourcePort
    typealias DidDrain = @Sendable (BackgroundMediaDrainObservation) async -> Void

    private struct LiveSource {
        let source: any BackgroundMediaUploadSourcePort
        let identity: ManagedUploadSourceIdentity
        let lease: OriginalReadLease
        var binding: BackgroundMediaTaskBinding?
        var released = false
    }
    private struct Session {
        let port: any BackgroundMediaSessionPort
        let recoveryBarrier: BackgroundMediaAttachmentBarrier
        var stream: UUID?
        var received: UInt64 = 0
        var queue: [BackgroundMediaSDKEvent] = []
        var draining = false
        var corruptSequence = false
        var unsafeIntents: Set<BackgroundMediaTaskID> = []
        var recovery: BackgroundMediaRecoveryReport?
    }

    private let store: any MediaOperationStorePort
    private let identity: RegistrationStoreIdentity
    private let originals: any OriginalAccessPort
    private let removalStore: (any OriginalStorePort)?
    private let admission: any BackgroundMediaStrictAdmissionPort
    private let captureAdmission: CaptureMediaAdmission
    private let makeSession: SessionFactory
    private let makeSource: SourceFactory
    private let didDrain: DidDrain
    private var sessions: [BackgroundMediaSessionIdentity: Session] = [:]
    private var connections: [BackgroundMediaSessionIdentity: Task<any BackgroundMediaSessionPort, Error>] = [:]
    private var consumers: [BackgroundMediaSessionIdentity: Task<Void, Never>] = [:]
    private var live: [BackgroundMediaTaskID: LiveSource] = [:]
    private var preparing: [BackgroundMediaTaskID: BackgroundMediaAttachmentBarrier] = [:]
    private var starts: [BackgroundMediaTaskID: MediaTarget] = [:]
    private var removalSeals: [MediaOperationID: OriginalRemovalAdmissionSeal] = [:]
    private var pending: [BackendStoreMutation] = []
    private var observedTerminals: [BackgroundMediaTaskBinding] = []
    private var captureWaits: [MediaOperationID: Set<MediaWaitReason>] = [:]
    private var captureWaitChanges: [MediaOperationID: [MediaWaitReason: BackendStoreChange]] = [:]
    private var synchronizingCapture: Task<Bool, Never>?
    private var captureStopRequested = Set<BackgroundMediaTaskID>()
    private var captureStopWaiters: [CheckedContinuation<Void, Never>] = []
    private var stoppedChanges: [BackgroundMediaTaskID: BackendStoreChange] = [:]
    private var localStops: [BackgroundMediaTaskID: TransportStopReceipt] = [:]
    private var confirmedLocalStops = Set<BackgroundMediaTaskID>()
    private var terminalProcessing = Set<BackgroundMediaTaskID>()
    private var signalledCaptureRevision: UInt64 = 0
    private(set) var retainedEvents: [BackgroundMediaSDKEvent] = []

    init(store: any MediaOperationStorePort, identity: RegistrationStoreIdentity,
         originals: any OriginalAccessPort,
         removalStore: (any OriginalStorePort)? = nil,
         admission: any BackgroundMediaStrictAdmissionPort = UnavailableBackgroundMediaStrictAdmission(),
         captureAdmission: CaptureMediaAdmission = CaptureMediaAdmission(),
         sessionFactory: @escaping SessionFactory, sourceFactory: @escaping SourceFactory,
         didDrain: @escaping DidDrain = { _ in }) {
        self.store = store; self.identity = identity; self.originals = originals; self.admission = admission
        self.removalStore = removalStore
        self.captureAdmission = captureAdmission
        makeSession = sessionFactory; makeSource = sourceFactory; self.didDrain = didDrain
    }

    func startUpload(_ plan: BackgroundMediaUploadPlan) async -> BackgroundMediaStartResult {
        guard !removalIsSealed(plan.context.target.original) else { return .refused(.removalBoundaryActive) }
        guard plan.context.storeIdentity == identity,
              case .original(let original) = plan.context.target,
              let fingerprint = try? BackgroundMediaRequestFingerprint.make(request: plan.request),
              let snapshot = await load() else { return .refused(.identityMismatch) }
        if let stored = snapshot.backgroundTasks.first(where: { $0.intent.id == plan.id }) {
            guard stored.intent.context == plan.context, stored.intent.session == plan.session,
                  stored.intent.taskDescription == plan.taskDescription, stored.intent.requestFingerprint == fingerprint,
                  case .upload(let session, _, let source) = stored.intent.source,
                  session == plan.macSession, source.id == plan.sourceID,
                  await confirms(stored) else { return .unknown }
            return .existing(stored)
        }
        guard !captureAdmission.snapshot().isHeld else { return .refused(.captureBoundaryActive) }
        guard starts[plan.id] == nil else { return .unknown }
        starts[plan.id] = plan.context.target
        defer { starts.removeValue(forKey: plan.id) }
        // This guard precedes beginAttempt, lease acquisition, source copy and
        // even the suspended SDK session/task factories in the normal root.
        let permission = await admission.permit(plan.context)
        guard case .succeeded(let permit) = permission else {
            if case .notExecuted = permission { return .refused(.strictAdmissionUnavailable) }
            return .refused(.strictAdmissionRejected)
        }
        guard permit.context == plan.context, !permit.evidence.rawValue.isEmpty else { return .refused(.identityMismatch) }
        guard !removalIsSealed(original) else { return .refused(.removalBoundaryActive) }
        guard !captureAdmission.snapshot().isHeld else { return .refused(.captureBoundaryActive) }
        guard let current = await load(),
              let request = current.requests.first(where: { $0.operation == plan.context.operation }),
              request.target == plan.context.target, request.registration == plan.context.registration,
              request.purpose == .upload, request.session == plan.macSession, request.canRun else {
            return .refused(.requestNotReady)
        }
        let begin = BackendStoreChange.requestTransition(command: command(), operation: request.operation,
            target: request.target, registration: request.registration, value: .beginAttempt(plan.context.attempt))
        guard !removalIsSealed(original) else { return .refused(.removalBoundaryActive) }
        guard await persist(begin) else { return .unknown }
        guard !removalIsSealed(original) else { return .unknown }
        guard case .succeeded(let lease) = await originals.acquireRead(original, operation: request.operation,
            leaseID: .init(rawValue: UUID().uuidString)) else { return .unknown }
        guard !captureAdmission.snapshot().isHeld, !removalIsSealed(original) else { return .unknown }
        do {
            let source = try await makeSource()
            guard !removalIsSealed(original) else { return .unknown }
            let copy = try await source.create(from: lease, id: plan.sourceID)
            live[plan.id] = .init(source: source, identity: copy, lease: lease)
            guard !captureAdmission.snapshot().isHeld, !removalIsSealed(original) else { return .unknown }
            let intent = BackgroundMediaTaskIntent(id: plan.id, context: plan.context, session: plan.session,
                taskDescription: plan.taskDescription, requestFingerprint: fingerprint,
                source: .upload(session: plan.macSession, lease: lease, source: copy))
            try intent.validate()
            guard await persist(.backgroundTask(command: command(), value: .prepared(intent))) else { return .unknown }
            guard !removalIsSealed(original) else { return .unknown }
            let barrier = BackgroundMediaAttachmentBarrier()
            preparing[plan.id] = barrier
            let result = await createAndResume(intent, plan: plan, source: source, lease: lease, barrier: barrier)
            await barrier.finish()
            preparing.removeValue(forKey: plan.id)
            return result
        } catch {
            // A failed copy/unknown commit may have left real resources. This
            // is not proof of non-execution or permission to release the lease.
            return .unknown
        }
    }

    /// No protected background download-file ingress exists yet. In particular,
    /// completion alone never creates TemporaryMedia or ownerClosed evidence.
    func startDownload(_ context: BackgroundMediaRequestContext) async -> BackgroundMediaStartResult {
        guard !removalIsSealed(context.target.original) else { return .refused(.removalBoundaryActive) }
        guard !captureAdmission.snapshot().isHeld else { return .refused(.captureBoundaryActive) }
        guard case .succeeded(let permit) = await admission.permit(context), permit.context == context else {
            return .refused(.strictAdmissionUnavailable)
        }
        return .refused(.downloadIngressUnavailable)
    }

    private func createAndResume(_ intent: BackgroundMediaTaskIntent, plan: BackgroundMediaUploadPlan,
        source: any BackgroundMediaUploadSourcePort, lease: OriginalReadLease,
        barrier: BackgroundMediaAttachmentBarrier) async -> BackgroundMediaStartResult {
        do {
            guard !removalIsSealed(intent.context.target.original) else { return .unknown }
            guard let owned = live[intent.id] else { return .unknown }
            let file = try await source.uploadFile(for: owned.identity, lease: lease)
            guard !removalIsSealed(intent.context.target.original) else { return .unknown }
            let session = try await session(for: intent.session)
            guard !removalIsSealed(intent.context.target.original), sessions[intent.session]?.recovery != nil else { return .unknown }
            guard case .succeeded(let binding) = await session.createSuspended(intent, request: plan.request, upload: file),
                  binding.session == intent.session, binding.taskDescription == intent.taskDescription,
                  binding.taskIdentifier > 0 else { return .unknown }
            live[intent.id]?.binding = binding
            try await source.retain(file.identity, lease: lease, for: binding)
            guard await persist(.backgroundTask(command: command(), value: .attached(intent, binding))) else { return .unknown }
            await barrier.finish()
            guard !removalIsSealed(intent.context.target.original) else { return .unknown }
            guard !captureAdmission.snapshot().isHeld else {
                await stop(intent, binding: binding, session: session)
                return .refused(.captureBoundaryActive)
            }
            // A real terminal may arrive before durable attach returns. It must
            // not be lost or turned into authority to resume a finished task.
            let sdkTerminal = await session.observeTerminal(binding)
            if observedTerminals.contains(binding) || {
                if case .succeeded(let terminal) = sdkTerminal { return terminal.binding == binding }
                return false
            }() {
                guard let value = await state(intent.id) else { return .unknown }
                return .existing(value)
            }
            guard case .inProgress = sdkTerminal else { return .unknown }
            guard case .succeeded(let permit) = await admission.permit(intent.context),
                  permit.context == intent.context, !permit.evidence.rawValue.isEmpty else {
                await stop(intent, binding: binding, session: session)
                return .refused(.strictAdmissionRejected)
            }
            guard !removalIsSealed(intent.context.target.original) else { return .unknown }
            guard await persist(.backgroundTask(command: command(), value: .resumeRequested(intent, binding))) else { return .unknown }
            guard !removalIsSealed(intent.context.target.original) else { return .unknown }
            guard let captureAuthorization = captureAdmission.authorizeResume() else {
                await stop(intent, binding: binding, session: session)
                return .refused(.captureBoundaryActive)
            }
            // Issuance is not dispatch. The SDK owner must consume this exact
            // authorization on its executor after the actor/queue hop.
            guard case .succeeded(let resumed) = await session.resume(binding, permit: permit,
                captureAuthorization: captureAuthorization), resumed == binding else {
                await stop(intent, binding: binding, session: session)
                return .refused(.sdkResumeUnavailable)
            }
            guard let value = await state(intent.id) else { return .unknown }
            return .started(value)
        } catch { return .unknown }
    }

    /// Returning success here means the *intent* is durable. Stop requests and
    /// actual SDK/file terminals remain independently observable facts.
    func control(_ operation: MediaOperationID, _ action: BackgroundMediaControl,
                 command: MediaOperationID) async -> BackendOutcome<MediaRequest> {
        guard let snapshot = await load(), let request = snapshot.requests.first(where: { $0.operation == operation }) else { return .unknown }
        let transition: MediaRequestTransition
        switch action {
        case .pause: transition = .pause
        case .resume: transition = .resume
        case .cancel: transition = .cancel
        case .wait(let reason, let active): transition = .wait(reason, active: active)
        }
        guard await persist(.requestTransition(command: command, operation: operation, target: request.target,
            registration: request.registration, value: transition)), let latest = await load(),
            let updated = latest.requests.first(where: { $0.operation == operation }) else { return .unknown }
        // Explicit resume changes only the person's intent; every start still
        // needs a new strict permit and current reconciliation of all waits.
        if updated.transport == .stopRequested || updated.intent != .running || !updated.waits.isEmpty {
            for state in latest.backgroundTasks where state.intent.context.operation == operation && state.terminal == nil {
                guard let binding = state.binding, let session = try? await session(for: state.intent.session) else { continue }
                await stop(state.intent, binding: binding, session: session)
            }
        }
        return .succeeded(updated)
    }

    func pauseAll() async -> BackendOutcome<[MediaRequest]> {
        guard let snapshot = await load() else { return .unknown }
        for request in snapshot.requests where request.intent != .cancelled && request.transport != .completed {
            guard case .succeeded = await control(request.operation, .pause, command: command()) else { return .unknown }
        }
        guard let latest = await load() else { return .unknown }
        return .succeeded(latest.requests)
    }

    func synchronizeCaptureWaits() async -> Bool {
        let revision = captureAdmission.snapshot().revision
        if revision != signalledCaptureRevision {
            signalledCaptureRevision = revision
            signalCaptureStopWaiters()
        }
        if let synchronizingCapture { return await synchronizingCapture.value }
        let work = Task { await applyCaptureWaits() }
        synchronizingCapture = work
        defer { synchronizingCapture = nil }
        return await work.value
    }

    private func applyCaptureWaits() async -> Bool {
        let reasons: Set<MediaWaitReason> = [.recording, .saving, .recovery]
        while true {
            // Resolve an unknown reply with its original payload/revision before
            // deciding whether the current owner requires another transition.
            for (operation, changes) in captureWaitChanges {
                for (reason, change) in changes {
                    guard await persist(change) else { return false }
                    if case .requestTransition(_, _, _, _, .wait(_, let active)) = change {
                        if active { captureWaits[operation, default: []].insert(reason) }
                        else { captureWaits[operation]?.remove(reason) }
                    }
                    captureWaitChanges[operation]?.removeValue(forKey: reason)
                }
            }
            let observation = captureAdmission.snapshot()
            guard let snapshot = await load() else { return false }
            var changed = false
            for request in snapshot.requests {
                for reason in reasons {
                    let active = observation.waits.contains(reason)
                    let owned = captureWaits[request.operation]?.contains(reason) == true
                    if !active, !request.waits.contains(reason) { captureWaits[request.operation]?.remove(reason) }
                    guard (active && !request.waits.contains(reason)) || (!active && owned && request.waits.contains(reason)) else { continue }
                    guard captureAdmission.snapshot().revision == observation.revision else { changed = true; break }
                    let change = BackendStoreChange.requestTransition(command: command(), operation: request.operation,
                        target: request.target, registration: request.registration, value: .wait(reason, active: active))
                    captureWaitChanges[request.operation, default: [:]][reason] = change
                    changed = true
                }
            }
            if !changed, captureAdmission.snapshot().revision == observation.revision { return true }
        }
    }

    /// Only this process's known SDK/source owners can satisfy this boundary.
    /// Copy/start/gap/old-source uncertainty returns unknown, never a fabricated
    /// stop or an unconditional wait for all hashes/readers/Mac acknowledgements.
    func waitForCaptureLocalStop(_ owner: CaptureMediaOwner) async -> CaptureMediaLocalStop {
        while true {
            guard captureAdmission.snapshot().owners[owner] != nil else { return .cancelled }
            guard await synchronizeCaptureWaits() else { return .unknown }
            guard starts.isEmpty, preparing.isEmpty, let snapshot = await load() else { return .unknown }
            guard !live.values.contains(where: { $0.binding == nil && !$0.released }) else { return .unknown }
            for request in snapshot.requests where request.transport == .active || request.transport == .stopRequested {
                guard snapshot.backgroundTasks.contains(where: {
                    $0.intent.context.operation == request.operation && $0.intent.context.attempt == request.attempt
                        && $0.intent.context.target == request.target && $0.intent.context.registration == request.registration
                }) else { return .unknown }
            }
            var historicalStops = Set<BackgroundMediaTaskID>()
            for state in snapshot.backgroundTasks {
                guard let owned = live[state.intent.id] else {
                    guard await confirmsHistoricalStop(state, snapshot: snapshot) else { return .unknown }
                    historicalStops.insert(state.intent.id)
                    continue
                }
                guard let binding = owned.binding else { return .unknown }
                if owned.released {
                    guard await recordLocalStop(state) else { return .unknown }
                } else {
                    if state.terminal != nil || observedTerminals.contains(binding) {
                        if !terminalProcessing.contains(state.intent.id) { return .unknown }
                    }
                    guard let port = try? await session(for: state.intent.session) else { return .unknown }
                    if state.terminal == nil, !captureStopRequested.contains(state.intent.id) {
                        guard await stop(state.intent, binding: binding, session: port) else { return .unknown }
                        captureStopRequested.insert(state.intent.id)
                    }
                }
            }
            guard captureAdmission.snapshot().owners[owner] != nil else { return .cancelled }
            if snapshot.backgroundTasks.allSatisfy({ historicalStops.contains($0.intent.id)
                || (live[$0.intent.id]?.released == true && confirmedLocalStops.contains($0.intent.id)) }) {
                guard starts.isEmpty, preparing.isEmpty else { return .unknown }
                return .ready
            }
            await withCheckedContinuation { captureStopWaiters.append($0) }
        }
    }

    private func signalCaptureStopWaiters() {
        let waiting = captureStopWaiters; captureStopWaiters.removeAll()
        waiting.forEach { $0.resume() }
    }

    private func confirmsHistoricalStop(_ state: BackgroundMediaTaskState, snapshot: BackendStoreSnapshot) async -> Bool {
        let context = state.intent.context
        guard let binding = state.binding, let terminal = state.terminal, let closed = state.ownerClosure,
              terminal.binding == binding, closed.binding == binding, closed.tasksJoined, closed.handlesClosed,
              let request = snapshot.requests.first(where: { $0.operation == context.operation }),
              request.attempt == context.attempt, request.target == context.target,
              request.registration == context.registration, request.transport == .stopped else { return false }
        // The durable stopped transition is the producer's post-lease-release
        // fact. Earlier SDK/ownerClosed alone is insufficient after a crash.
        // A newer request attempt cannot stand in for this historical proof.
        return await confirms(state)
    }

    private func removalIsSealed(_ original: OriginalContent) -> Bool {
        removalSeals.values.contains { $0.target.original == original }
    }

    /// Observation only: never request cancellation, adopt an old source or
    /// manufacture a stopped transition in order to satisfy a removal.
    func sealForRemoval(_ seal: OriginalRemovalAdmissionSeal) async -> BackendOutcome<OriginalRemovalTransportFence> {
        if let existing = removalSeals[seal.target.operation], !existing.exactlyMatches(seal) { return .unknown }
        guard !removalSeals.values.contains(where: {
            $0.target.original == seal.target.original && $0.target.operation != seal.target.operation
        }) else { return .notExecuted }
        removalSeals[seal.target.operation] = seal
        let original = seal.target.original
        guard let removalStore,
              !starts.values.contains(where: { $0.original == original }),
              !preparing.keys.contains(where: { live[$0]?.lease.original == original }),
              !live.values.contains(where: { $0.lease.original == original && (!$0.released || $0.binding == nil) }),
              case .succeeded(let inventory) = await removalStore.loadRemovalTransportInventory(original),
              let snapshot = await load(), inventory.matchesProjection(snapshot) else { return .unknown }
        let stops: [TransportStopReceipt]
        if let historical = OriginalRemovalTransportHistory.stoppedTasks(original, backend: snapshot) { stops = historical }
        else if OriginalRemovalTransportHistory.neverStartedForRemoval(original, backend: snapshot),
                !snapshot.backgroundTasks.contains(where: { $0.intent.context.target.original == original }),
                snapshot.requests.filter({ $0.target.original == original }).allSatisfy({
                    $0.attempt == nil && $0.session == nil && $0.transport == .queued
                }) { stops = [] }
        else { return .unknown }
        let fence = OriginalRemovalTransportFence(seal: seal, inventory: inventory, stops: stops)
        guard fence.validatesHistory(snapshot) else { return .unknown }
        for task in inventory.tasks {
            guard await confirmsHistoricalStop(task, snapshot: snapshot) else { return .unknown }
            if let owned = live[task.intent.id] {
                guard owned.released, let binding = task.binding,
                      PublicationStoreBoundary.exact(owned.binding, Optional(binding)),
                      case .upload(_, let lease, let source) = task.intent.source,
                      PublicationStoreBoundary.exact(owned.lease, lease), PublicationStoreBoundary.exact(owned.identity, source) else { return .unknown }
            }
        }
        guard live.allSatisfy({ id, owned in
            owned.lease.original != original || inventory.tasks.contains { PublicationStoreBoundary.exact($0.intent.id, id) }
        }) else { return .unknown }
        var sessionInventory = Array(sessions.keys)
        for task in inventory.tasks {
            if !sessionInventory.contains(task.intent.session) { sessionInventory.append(task.intent.session) }
        }
        for sessionIdentity in sessionInventory {
            guard let port = try? await session(for: sessionIdentity),
                  sessions[sessionIdentity]?.corruptSequence == false,
                  sessions[sessionIdentity]?.recovery != nil,
                  !(sessions[sessionIdentity]?.unsafeIntents.contains(where: { id in
                      inventory.tasks.contains { $0.intent.id == id }
                  }) ?? true),
                  !retainedEvents.contains(where: { $0.session == sessionIdentity }),
                  case .succeeded(let observed) = await port.enumerate() else { return .unknown }
            guard observed.allSatisfy({ PublicationStoreBoundary.exact($0.session, sessionIdentity) }),
                  Set(observed.map(\.taskIdentifier)).count == observed.count else { return .unknown }
            for observation in observed {
                let matches = snapshot.backgroundTasks.filter {
                    guard let binding = $0.binding else { return false }
                    return PublicationStoreBoundary.exact(binding.session, observation.session)
                        && binding.taskIdentifier == observation.taskIdentifier
                        && binding.taskDescription.utf8.elementsEqual((observation.taskDescription ?? "").utf8)
                }
                guard matches.count == 1, let matched = matches.first else { return .unknown }
                let kind: BackgroundMediaTaskKind
                switch matched.intent.source { case .upload: kind = .upload; case .download: kind = .download }
                guard observation.kind == kind else { return .unknown }
                if matched.intent.context.target.original == original {
                    guard observation.state == .completed else { return .unknown }
                }
            }
        }
        for fact in inventory.journal {
            guard case .committed(let receipt) = await store.lookupCommit(fact.mutation),
                  PublicationStoreBoundary.exact(receipt, fact.commit) else { return .unknown }
        }
        guard !starts.values.contains(where: { $0.original == original }),
              case .succeeded(let latest) = await removalStore.loadRemovalTransportInventory(original), latest == inventory,
              case .succeeded(let originals) = await removalStore.loadOriginalState(), originals.reconciliationEpoch == inventory.epoch,
              let state = originals.logicalOriginals.first(where: { PublicationStoreBoundary.exact($0.original, original) }),
              inventory.tasks.allSatisfy({ task in
                  if case .upload(_, let lease, _) = task.intent.source { return !state.readers.contains(lease) }
                  return false
              }) else { return .unknown }
        return .succeeded(fence)
    }

    func releaseAfterRemoval(_ release: OriginalRemovalAdmissionRelease) async -> Bool {
        guard let seal = removalSeals[release.seal.target.operation], seal.exactlyMatches(release.seal),
              case .succeeded = await sealForRemoval(seal), let removalStore,
              case .succeeded(let snapshot) = await removalStore.loadOriginalState(), release.validates(snapshot) else { return false }
        removalSeals.removeValue(forKey: seal.target.operation)
        return true
    }

    @discardableResult private func stop(_ intent: BackgroundMediaTaskIntent, binding: BackgroundMediaTaskBinding,
                      session: any BackgroundMediaSessionPort) async -> Bool {
        guard await persist(.backgroundTask(command: command(), value: .stopRequested(intent))) else { return false }
        await session.requestStop(binding)
        return true
    }

    func recover(_ identity: BackgroundMediaSessionIdentity) async -> BackendOutcome<BackgroundMediaRecoveryReport> {
        do {
            let existing = sessions[identity] != nil
            let port = try await session(for: identity)
            if existing {
                let result = await BackgroundMediaRecovery(store: store, identity: self.identity).reconcile(identity, session: port)
                guard case .succeeded(let report) = result else {
                    sessions[identity]?.recovery = nil
                    return .unknown
                }
                install(report)
                await sessions[identity]?.recoveryBarrier.finish()
            }
            guard let report = sessions[identity]?.recovery else { return .unknown }
            return .succeeded(report)
        } catch { return .unknown }
    }

    private func session(for identity: BackgroundMediaSessionIdentity) async throws -> any BackgroundMediaSessionPort {
        if let opening = connections[identity] { return try await opening.value }
        if let existing = sessions[identity] { return existing.port }
        let opening = Task { try await connect(identity) }
        connections[identity] = opening
        defer { connections.removeValue(forKey: identity) }
        return try await opening.value
    }

    private func connect(_ identity: BackgroundMediaSessionIdentity) async throws -> any BackgroundMediaSessionPort {
        let port = try await makeSession(identity)
        let stream = try await port.events()
        let barrier = BackgroundMediaAttachmentBarrier()
        sessions[identity] = Session(port: port, recoveryBarrier: barrier)
        consumers[identity] = Task { [weak self] in
            for await event in stream { await self?.receive(event) }
        }
        let result = await BackgroundMediaRecovery(store: store, identity: self.identity).reconcile(identity, session: port)
        if case .succeeded(let report) = result {
            install(report)
            await barrier.finish()
        }
        // Enumeration failure holds the recovery barrier, and thus completion,
        // until a later explicit recovery succeeds. No missing-task release.
        return port
    }

    private func receive(_ event: BackgroundMediaSDKEvent) async {
        guard var session = sessions[event.session] else { retainedEvents.append(event); return }
        if session.stream == nil { session.stream = event.stream }
        guard !session.corruptSequence, session.stream == event.stream,
              session.received < UInt64.max, event.sequence == session.received + 1 else {
            session.corruptSequence = true; sessions[event.session] = session
            retainedEvents.append(event); return
        }
        session.received = event.sequence
        session.queue.append(event)
        sessions[event.session] = session
        if case .taskTerminal(let terminal) = event.value { observedTerminals.append(terminal.binding) }
        await drain(event.session)
    }

    func retryHeldEvents() async {
        for identity in Array(sessions.keys) {
            if sessions[identity]?.recovery == nil, let port = sessions[identity]?.port,
               case .succeeded(let report) = await BackgroundMediaRecovery(store: store, identity: self.identity).reconcile(identity, session: port) {
                install(report)
                await sessions[identity]?.recoveryBarrier.finish()
            }
            await drain(identity)
        }
    }

    private func drain(_ identity: BackgroundMediaSessionIdentity) async {
        guard sessions[identity]?.draining == false, sessions[identity]?.corruptSequence == false else { return }
        sessions[identity]?.draining = true
        defer { sessions[identity]?.draining = false }
        await sessions[identity]?.recoveryBarrier.wait()
        while let event = sessions[identity]?.queue.first {
            guard sessions[identity]?.recovery != nil else { return }
            guard await process(event) else { return }
            sessions[identity]?.queue.removeFirst()
        }
    }

    private func process(_ event: BackgroundMediaSDKEvent) async -> Bool {
        switch event.value {
        case .finishedEvents:
            await didDrain(.init(session: event.session, stream: event.stream, sequence: event.sequence))
            return true
        case .sessionInvalidated: return true
        case .downloadArtifactUnavailable:
            retainedEvents.append(event)
            return true
        case .taskTerminal(let terminal): return await processTerminal(terminal, event: event)
        case .unknownTaskTerminal(let observation, let outcome):
            guard let snapshot = await load() else { return false }
            let matches = snapshot.backgroundTasks.filter {
                guard let binding = $0.binding else { return false }
                let expected: BackgroundMediaTaskKind
                switch $0.intent.source { case .upload: expected = .upload; case .download: expected = .download }
                return binding.session == observation.session && binding.taskIdentifier == observation.taskIdentifier
                    && binding.taskDescription == observation.taskDescription && observation.kind == expected
            }
            guard matches.count == 1, let binding = matches.first?.binding else {
                retainedEvents.append(event); return true
            }
            return await processTerminal(.init(binding: binding, outcome: outcome), event: event)
        }
    }

    private func processTerminal(_ terminal: BackgroundMediaSDKTerminal, event: BackgroundMediaSDKEvent) async -> Bool {
        defer { signalCaptureStopWaiters() }
        guard var snapshot = await load() else { return false }
        if let gap = snapshot.backgroundTasks.first(where: {
            $0.intent.session == terminal.binding.session && $0.intent.taskDescription == terminal.binding.taskDescription
                && $0.binding == nil
        }), let barrier = preparing[gap.intent.id] {
            await barrier.wait()
            guard let latest = await load() else { return false }
            snapshot = latest
        }
        let states = snapshot.backgroundTasks.filter { $0.binding == terminal.binding }
        guard states.count == 1, let state = states.first,
              sessions[event.session]?.unsafeIntents.contains(state.intent.id) == false,
              await confirms(state) else { retainedEvents.append(event); return false }
        terminalProcessing.insert(state.intent.id)
        defer { terminalProcessing.remove(state.intent.id) }
        guard state.terminal == nil || state.terminal == terminal,
              await persist(.backgroundTask(command: command(), value: .terminal(state.intent, terminal))) else { return false }
        guard var owned = live[state.intent.id] else {
            // Reopened source/lease adoption is deliberately unavailable. The
            // actual terminal is durable in its old context; unknown owners and
            // readers remain, independent of OS delivery completion.
            return true
        }
        guard owned.binding == terminal.binding else { return false }
        if owned.released { return await recordLocalStop(state) }
        do {
            let closed = try await owned.source.finish(owned.identity, lease: owned.lease, terminal: terminal)
            guard closed.binding == terminal.binding, closed.uploadSource == owned.identity,
                  closed.tasksJoined, closed.handlesClosed,
                  await persist(.backgroundTask(command: command(), value: .ownerClosed(state.intent, closed))) else { return false }
            guard case .succeeded(let receipt) = await originals.releaseRead(owned.lease), receipt.lease == owned.lease else { return false }
            owned.released = true
            live[state.intent.id] = owned
            return await recordLocalStop(state)
        } catch { return false }
    }

    private func recordLocalStop(_ state: BackgroundMediaTaskState) async -> Bool {
        if localStops[state.intent.id] != nil { return true }
        if let retained = stoppedChanges[state.intent.id] {
            guard await persist(retained),
                  case .requestTransition(_, _, _, _, .stopped(let receipt)) = retained else { return false }
            localStops[state.intent.id] = receipt
            confirmedLocalStops.insert(state.intent.id)
            return true
        }
        guard live[state.intent.id]?.released == true, let latest = await load(),
              let request = latest.requests.first(where: { $0.operation == state.intent.context.operation }) else { return false }
        let context = state.intent.context
        // A delayed terminal may close its own resources without changing a
        // newer attempt, completed request, registration or any remote result.
        guard request.attempt == context.attempt, request.target == context.target,
              request.registration == context.registration, request.transport != .completed else {
            confirmedLocalStops.insert(state.intent.id)
            return true
        }
        let receipt = TransportStopReceipt(operation: context.operation, attempt: context.attempt,
            target: context.target, registration: context.registration)
        let change = BackendStoreChange.requestTransition(command: command(), operation: context.operation,
            target: context.target, registration: context.registration, value: .stopped(receipt))
        stoppedChanges[state.intent.id] = change
        guard await persist(change) else { return false }
        localStops[state.intent.id] = receipt
        confirmedLocalStops.insert(state.intent.id)
        return true
    }

    private func load() async -> BackendStoreSnapshot? {
        guard case .loaded(let snapshot) = await store.load(), snapshot.storeIdentity == identity else { return nil }
        return snapshot
    }

    private func install(_ report: BackgroundMediaRecoveryReport) {
        sessions[report.session]?.recovery = report
        sessions[report.session]?.unsafeIntents = Set(report.tasks.compactMap { value in
            switch value.disposition {
            case .duplicateDescription, .numericIdentifierReused, .kindMismatch, .unconfirmedJournal: value.intent
            default: nil
            }
        })
    }

    private func state(_ id: BackgroundMediaTaskID) async -> BackgroundMediaTaskState? {
        await load()?.backgroundTasks.first { $0.intent.id == id }
    }

    private func confirms(_ state: BackgroundMediaTaskState) async -> Bool {
        guard !state.events.isEmpty else { return false }
        for event in state.events {
            guard case .committed(let receipt) = await store.lookupCommit(event.mutation), receipt == event.commit else { return false }
        }
        return true
    }

    /// Lost replies are reconciled with the exact retained mutation. A new CAS
    /// revision is used only after a definite revision-conflict rejection.
    private func persist(_ requested: BackendStoreChange) async -> Bool {
        if case .backgroundTask(_, let value) = requested, let state = await state(value.intent.id),
           let stored = state.events.first(where: { $0.change == value }) {
            guard case .committed(let receipt) = await store.lookupCommit(stored.mutation), receipt == stored.commit else { return false }
            return true
        }
        if let retained = pending.first(where: { mutation in
            if case .backgroundTask(_, let lhs) = mutation.change, case .backgroundTask(_, let rhs) = requested { return lhs == rhs }
            return mutation.change == requested
        }) {
            guard case .committed(let receipt) = await store.lookupCommit(retained),
                  receipt.matches(retained.change.key, revision: retained.expectedRevision) else { return false }
            pending.removeAll { $0 == retained }
            return true
        }
        // Preserve the command generated for this call through CAS retries.
        let change = requested
        for _ in 0..<3 {
            guard let snapshot = await load() else { return false }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: change, expectedStoreIdentity: identity)
            pending.append(mutation)
            let result = await store.commit(mutation)
            if case .rejected(.revisionConflict) = result { pending.removeAll { $0 == mutation }; continue }
            if case .rejected = result { pending.removeAll { $0 == mutation }; return false }
            guard case .committed(let receipt) = await store.lookupCommit(mutation),
                  receipt.matches(change.key, revision: mutation.expectedRevision) else { return false }
            pending.removeAll { $0 == mutation }
            return true
        }
        return false
    }

    private func command() -> MediaOperationID { .init(rawValue: "background-" + UUID().uuidString) }
}
