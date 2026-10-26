import Foundation

nonisolated protocol BackgroundMediaUploadSourcePort: Sendable {
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity
    func createChunk(from lease: OriginalReadLease, id: ManagedUploadSourceID,
                     range: UploadChunkRange) async throws -> ManagedUploadChunkIdentity
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) async throws -> BackgroundMediaUploadFile
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                for binding: BackgroundMediaTaskBinding) async throws
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                terminal: BackgroundMediaSDKTerminal) async throws -> BackgroundMediaOwnerClosure
}

nonisolated extension BackgroundMediaUploadSourcePort {
    func createChunk(from lease: OriginalReadLease, id: ManagedUploadSourceID,
                     range: UploadChunkRange) async throws -> ManagedUploadChunkIdentity { throw BackendContractError.unavailable }
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

/// Explicit one-chunk input. Request creation follows strict admission and
/// verified local materialization; no URL, body or credentials are persisted.
nonisolated struct BackgroundMediaUploadChunkPlan: Sendable, Encodable {
    let id: BackgroundMediaTaskID
    let context: BackgroundMediaRequestContext
    let session: BackgroundMediaSessionIdentity
    let taskDescription: String
    let sourceID: ManagedUploadSourceID
    let range: UploadChunkRange
    let metadata: UploadChunkMetadataSelection
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
actor BackgroundMediaCoordinator: OriginalRemovalBackgroundPort, BackgroundInvalidationTerminationPort, MediaRequestControlPort {
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
    private struct ChunkStart {
        let key: Data
        let task: Task<BackgroundMediaStartResult, Never>
        var finished = false
    }
    private var chunkStarts: [Data: ChunkStart] = [:]
    private var removalSeals: [MediaOperationID: OriginalRemovalAdmissionSeal] = [:]
    private struct InvalidationStop {
        let record: InvalidationRecord
        let epoch: ReaderReconciliationEpoch
        let binding: BackgroundMediaTaskBinding
    }
    private var invalidationStops: [InvalidationStop] = []
    private var pending: [BackendStoreMutation] = []
    private var personPlans: [Data: MediaPersonControlPlan] = [:]
    private var personPending: [Data: BackendStoreMutation] = [:]
    private var personBusy = Set<Data>()
    private var personOriginated = Set<Data>()
    private var personStops: [Data: Task<[MediaPersonControlStopResult], Never>] = [:]
    private var personBindingStops: [Data: Task<Bool, Never>] = [:]
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
            let result = await createAndResume(intent, request: plan.request, source: source, lease: lease, barrier: barrier)
            await barrier.finish()
            preparing.removeValue(forKey: plan.id)
            return result
        } catch {
            // A failed copy/unknown commit may have left real resources. This
            // is not proof of non-execution or permission to release the lease.
            return .unknown
        }
    }

    /// Same fixed input joins its retained work, including an unknown result.
    /// A different plan for the operation cannot race an active materializer.
    func startUploadChunk(_ plan: BackgroundMediaUploadChunkPlan,
                          requests: any BackgroundMediaUploadChunkRequestPort) async -> BackgroundMediaStartResult {
        guard plan.context.storeIdentity == identity,
              let key = try? UploadMetadataValidation.canonicalBytes(plan) else { return .refused(.identityMismatch) }
        let operation = Data(plan.context.operation.rawValue.utf8)
        if let old = chunkStarts[operation] {
            if old.key == key { return await old.task.value }
            guard old.finished else { return .refused(.requestNotReady) }
        }
        let work = Task { await self.performChunkStart(plan, requests: requests) }
        chunkStarts[operation] = .init(key: key, task: work)
        let result = await work.value
        if chunkStarts[operation]?.key == key { chunkStarts[operation]?.finished = true }
        return result
    }

    private func performChunkStart(_ plan: BackgroundMediaUploadChunkPlan,
                                   requests: any BackgroundMediaUploadChunkRequestPort) async -> BackgroundMediaStartResult {
        let original = plan.range.binding.original
        guard !removalIsSealed(original) else { return .refused(.removalBoundaryActive) }
        guard UploadMetadataValidation.exact(plan.context.target, MediaTarget.original(original)),
              let snapshot = await load() else { return .refused(.identityMismatch) }
        if let stored = snapshot.backgroundTasks.first(where: { $0.intent.id == plan.id }) {
            guard case .uploadChunk(_, let chunk, let metadata) = stored.intent.source,
                  UploadMetadataValidation.exact(stored.intent.context, plan.context),
                  UploadMetadataValidation.exact(stored.intent.session, plan.session),
                  stored.intent.taskDescription.utf8.elementsEqual(plan.taskDescription.utf8),
                  UploadMetadataValidation.exact(chunk.source.id, plan.sourceID), chunk.descriptor.range == plan.range,
                  metadata == plan.metadata, await confirms(stored) else { return .unknown }
            return .existing(stored) // No request builder, copy, adoption or SDK call.
        }
        guard !captureAdmission.snapshot().isHeld else { return .refused(.captureBoundaryActive) }
        guard starts[plan.id] == nil else { return .refused(.requestNotReady) }
        starts[plan.id] = plan.context.target
        defer { starts.removeValue(forKey: plan.id) }
        // Default unavailable stays before begin/lease/source/request/SDK factories.
        let permission = await admission.permit(plan.context)
        guard case .succeeded(let permit) = permission else {
            if case .notExecuted = permission { return .refused(.strictAdmissionUnavailable) }
            return .refused(.strictAdmissionRejected)
        }
        guard UploadMetadataValidation.exact(permit.context, plan.context), !permit.evidence.rawValue.isEmpty else { return .refused(.identityMismatch) }
        guard !captureAdmission.snapshot().isHeld, !removalIsSealed(original) else { return .refused(.requestNotReady) }
        do {
            guard let view = await chunkView(original) else { return .unknown }
            try BackgroundUploadChunkAdmission.requireBeforeAttempt(context: plan.context, range: plan.range, metadata: plan.metadata,
                taskID: plan.id, sourceID: plan.sourceID, view: view)
        } catch { return .refused(.requestNotReady) }
        guard !captureAdmission.snapshot().isHeld, !removalIsSealed(original) else { return .refused(.requestNotReady) }
        let begin = BackendStoreChange.requestTransition(command: command(), operation: plan.context.operation,
            target: plan.context.target, registration: plan.context.registration, value: .beginAttempt(plan.context.attempt))
        guard await persist(begin), await chunkReservationCurrent(plan, lease: nil) else { return .unknown }
        guard case .succeeded(let lease) = await originals.acquireRead(original, operation: plan.context.operation,
            leaseID: .init(rawValue: UUID().uuidString)) else { return .unknown }
        guard await chunkReservationCurrent(plan, lease: lease) else { return .unknown }
        do {
            let source = try await makeSource()
            guard await chunkReservationCurrent(plan, lease: lease) else { return .unknown }
            let chunk = try await source.createChunk(from: lease, id: plan.sourceID, range: plan.range)
            // Keep this exact owner even if a later response/scope is unknown.
            live[plan.id] = .init(source: source, identity: chunk.source, lease: lease)
            try chunk.validate()
            guard chunk.descriptor.range == plan.range, UploadMetadataValidation.exact(chunk.source.id, plan.sourceID),
                  await chunkReservationCurrent(plan, lease: lease) else { return .unknown }
            let request = try await requests.makeRequest(context: plan.context, descriptor: chunk.descriptor)
            guard await chunkReservationCurrent(plan, lease: lease) else { return .unknown }
            let fingerprint = try BackgroundMediaRequestFingerprint.makeUploadChunk(request: request, descriptor: chunk.descriptor)
            let intent = BackgroundMediaTaskIntent(id: plan.id, context: plan.context, session: plan.session,
                taskDescription: plan.taskDescription, requestFingerprint: fingerprint,
                source: .uploadChunk(lease: lease, chunk: chunk, metadata: plan.metadata))
            guard await chunkCurrent(intent), await persist(.backgroundTask(command: command(), value: .prepared(intent))),
                  await chunkCurrent(intent) else { return .unknown }
            let barrier = BackgroundMediaAttachmentBarrier(); preparing[plan.id] = barrier
            let result = await createAndResume(intent, request: request, source: source, lease: lease, barrier: barrier)
            await barrier.finish(); preparing.removeValue(forKey: plan.id)
            return result
        } catch { return .unknown }
    }

    /// Advisory coherent read. The writer independently repeats the complete
    /// history/order/current guard at prepared and resumeRequested commits.
    private func chunkView(_ original: OriginalContent) async -> BackgroundUploadChunkAdmissionView? {
        guard let removalStore else { return nil }
        for _ in 0..<3 {
            guard let first = await load(), case .succeeded(let originals) = await removalStore.loadOriginalState() else { return nil }
            if first.revision != originals.revision { continue }
            guard case .succeeded(let inventory) = await removalStore.loadRemovalTransportInventory(original),
                  inventory.storeIdentity == identity, inventory.matchesProjection(first) else { continue }
            for fact in inventory.journal {
                guard case .committed(let receipt) = await store.lookupCommit(fact.mutation),
                      UploadMetadataValidation.exact(receipt, fact.commit) else { return nil }
            }
            guard let latest = await load(), latest.revision == first.revision,
                  case .succeeded(let after) = await removalStore.loadOriginalState(), after.revision == latest.revision,
                  after == originals, inventory.matchesProjection(latest),
                  case .succeeded(let finalInventory) = await removalStore.loadRemovalTransportInventory(original),
                  finalInventory == inventory,
                  let final = await load(), final.revision == latest.revision else { continue }
            return .init(revision: final.revision, storeIdentity: final.storeIdentity, registrations: final.registrations,
                requests: final.requests, originals: after.logicalOriginals, queries: final.uploadMetadataQueries,
                observations: final.uploadMetadataObservations, tasks: final.backgroundTasks, journal: inventory.journal)
        }
        return nil
    }

    private func chunkReservationCurrent(_ plan: BackgroundMediaUploadChunkPlan, lease: OriginalReadLease?) async -> Bool {
        guard !captureAdmission.snapshot().isHeld, !removalIsSealed(plan.range.binding.original),
              let view = await chunkView(plan.range.binding.original) else { return false }
        do {
            try BackgroundUploadChunkAdmission.requireReservedAttempt(context: plan.context, range: plan.range, metadata: plan.metadata,
                taskID: plan.id, sourceID: plan.sourceID, lease: lease, view: view)
            return !captureAdmission.snapshot().isHeld && !removalIsSealed(plan.range.binding.original)
        } catch { return false }
    }

    private func chunkCurrent(_ intent: BackgroundMediaTaskIntent) async -> Bool {
        guard case .uploadChunk = intent.source else { return true }
        guard !captureAdmission.snapshot().isHeld, !removalIsSealed(intent.context.target.original),
              let view = await chunkView(intent.context.target.original) else { return false }
        do {
            try BackgroundUploadChunkAdmission.requireCurrentAttempt(intent, view: view)
            return !captureAdmission.snapshot().isHeld && !removalIsSealed(intent.context.target.original)
        } catch { return false }
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

    private func createAndResume(_ intent: BackgroundMediaTaskIntent, request: URLRequest,
        source: any BackgroundMediaUploadSourcePort, lease: OriginalReadLease,
        barrier: BackgroundMediaAttachmentBarrier) async -> BackgroundMediaStartResult {
        do {
            guard !removalIsSealed(intent.context.target.original), await chunkCurrent(intent) else { return .unknown }
            guard let owned = live[intent.id] else { return .unknown }
            let file = try await source.uploadFile(for: owned.identity, lease: lease)
            guard !removalIsSealed(intent.context.target.original), await chunkCurrent(intent) else { return .unknown }
            let session = try await session(for: intent.session)
            guard !removalIsSealed(intent.context.target.original), sessions[intent.session]?.recovery != nil,
                  await chunkCurrent(intent) else { return .unknown }
            guard case .succeeded(let binding) = await session.createSuspended(intent, request: request, upload: file),
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
            guard await chunkCurrent(intent) else {
                await stop(intent, binding: binding, session: session)
                return .refused(.requestNotReady)
            }
            guard case .succeeded(let permit) = await admission.permit(intent.context),
                  permit.context == intent.context, !permit.evidence.rawValue.isEmpty else {
                await stop(intent, binding: binding, session: session)
                return .refused(.strictAdmissionRejected)
            }
            guard !removalIsSealed(intent.context.target.original) else { return .unknown }
            guard await chunkCurrent(intent) else {
                await stop(intent, binding: binding, session: session); return .unknown
            }
            guard await persist(.backgroundTask(command: command(), value: .resumeRequested(intent, binding))) else { return .unknown }
            guard !removalIsSealed(intent.context.target.original) else { return .unknown }
            guard await chunkCurrent(intent) else {
                await stop(intent, binding: binding, session: session); return .unknown
            }
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

    func submitPersonControl(_ plan: MediaPersonControlPlan) async -> MediaPersonControlResult {
        await personControl(plan, allowNew: true)
    }
    func lookupPersonControl(_ plan: MediaPersonControlPlan) async -> MediaPersonControlResult {
        await personControl(plan, allowNew: false)
    }

    private func personControl(_ plan: MediaPersonControlPlan, allowNew: Bool) async -> MediaPersonControlResult {
        do { try plan.validate() } catch { return .rejected(.invalidValue) }
        guard plan.storeIdentity == identity else { return .rejected(.identityMismatch) }
        let key = Data(plan.parent.rawValue.utf8)
        if let old = personPlans.values.first(where: { $0.parent == plan.parent }),
           !MediaPersonControlValueValidation.exact(old, plan) { return .rejected(.identityMismatch) }
        guard personBusy.insert(key).inserted else { return .unknown }
        defer { personBusy.remove(key) }
        personPlans[key] = plan
        var committed: StoredMediaPersonControlPlan?
        if let mutation = personPending[key] {
            // A lost response is never a new submission or a fresh CAS base.
            switch await store.lookupCommit(mutation) {
            case .committed(let receipt):
                committed = await confirmedPersonRecord(plan, receipt: receipt, mutation: mutation)
                guard committed != nil else { return .unknown }
                personPending.removeValue(forKey: key)
            case .rejected(let reason): return .rejected(reason)
            default: return .unknown
            }
        } else {
            guard let snapshot = await load() else { return .unknown }
            if let old = snapshot.personControls.first(where: { $0.plan.parent == plan.parent }) {
                guard MediaPersonControlValueValidation.exact(old.plan, plan), old.isCommitted else { return .rejected(.identityMismatch) }
                switch await store.lookupCommit(old.mutation) {
                case .committed(let receipt):
                    guard MediaPersonControlValueValidation.exact(receipt, old.commit) else { return .rejected(.identityMismatch) }
                    committed = await confirmedPersonRecord(plan, receipt: receipt, mutation: old.mutation)
                case .rejected(let reason): return .rejected(reason)
                default: return .unknown
                }
            } else {
                guard allowNew else { return .unknown }
                for attempt in 0..<3 {
                    guard let current = await load() else { return .unknown }
                    let mutation = BackendStoreMutation(expectedRevision: current.revision,
                        change: .personControl(plan), expectedStoreIdentity: identity)
                    personPending[key] = mutation; personOriginated.insert(key)
                    let result = await store.commit(mutation)
                    if case .rejected(.revisionConflict) = result {
                        personPending.removeValue(forKey: key)
                        if attempt == 2 {
                            personOriginated.remove(key)
                            return .rejected(.revisionConflict)
                        }
                        continue // Same fixed plan; only a definite CAS conflict permits re-evaluation.
                    }
                    if case .rejected(let reason) = result {
                        personPending.removeValue(forKey: key); personOriginated.remove(key)
                        return .rejected(reason)
                    }
                    guard case .committed(let receipt) = await store.lookupCommit(mutation) else { return .unknown }
                    committed = await confirmedPersonRecord(plan, receipt: receipt, mutation: mutation)
                    guard committed != nil else { return .unknown }
                    personPending.removeValue(forKey: key)
                    break
                }
            }
        }
        guard let record = committed else { return .unknown }
        // A journal entry cannot recreate a live SDK-stop capability on reopen.
        guard personOriginated.contains(key) else {
            return .recorded(record, stops: record.children.map { child in
                .init(child: child.child.command, disposition: child.decision == .recorded && plan.action != .resumeIntent ? .notRequested : .notRequired)
            })
        }
        let work: Task<[MediaPersonControlStopResult], Never>
        if let existing = personStops[key] { work = existing }
        else {
            work = Task { await self.stopPersonChildren(record) }
            personStops[key] = work
        }
        let stops = await work.value
        guard let latest = await load(), latest.personControls.contains(where: {
            MediaPersonControlValueValidation.exact($0.plan, plan) && MediaPersonControlValueValidation.exact($0.commit, record.commit)
        }) else { return .unknown }
        return .recorded(record, stops: stops)
    }

    private func confirmedPersonRecord(_ plan: MediaPersonControlPlan, receipt: BackendCommitReceipt,
        mutation: BackendStoreMutation) async -> StoredMediaPersonControlPlan? {
        guard receipt.matches(.personControl(plan.parent), revision: mutation.expectedRevision),
              MediaPersonControlValueValidation.exact(receipt.key, mutation.change.key),
              let snapshot = await load(), let record = snapshot.personControls.first(where: { $0.plan.parent == plan.parent }),
              record.isCommitted, MediaPersonControlValueValidation.exact(record.plan, plan),
              MediaPersonControlValueValidation.exact(record.commit, receipt),
              MediaPersonControlValueValidation.exact(record.mutation, mutation) else { return nil }
        return record
    }

    private func stopPersonChildren(_ record: StoredMediaPersonControlPlan) async -> [MediaPersonControlStopResult] {
        await withTaskGroup(of: MediaPersonControlStopResult.self) { group in
            for child in record.children {
                group.addTask {
                    let disposition: MediaPersonControlStopDisposition
                    if child.decision != .recorded || record.plan.action == .resumeIntent { disposition = .notRequired }
                    else { disposition = await self.stopPersonChild(child.child, plan: record.plan) }
                    return .init(child: child.child.command, disposition: disposition)
                }
            }
            var values: [MediaPersonControlStopResult] = []
            for await value in group { values.append(value) }
            return record.children.map { child in
                values.first(where: { MediaPersonControlValueValidation.exact($0.child, child.child.command) })
                    ?? .init(child: child.child.command, disposition: .unknown)
            }
        }
    }

    private func currentPersonRequest(_ child: MediaPersonControlChild, plan: MediaPersonControlPlan) async -> BackendStoreSnapshot? {
        guard let snapshot = await load(), let request = snapshot.requests.first(where: { $0.operation == child.target.operation }),
              child.target.matches(request),
              (request.intent == .paused || request.intent == .cancelled || request.transport == .stopRequested),
              snapshot.personControls.contains(where: {
                  MediaPersonControlValueValidation.exact($0.plan, plan) && $0.isCommitted
              }) else { return nil }
        return snapshot
    }

    private func stopPersonChild(_ child: MediaPersonControlChild, plan: MediaPersonControlPlan) async -> MediaPersonControlStopDisposition {
        guard let snapshot = await currentPersonRequest(child, plan: plan) else { return .unknown }
        let related = snapshot.backgroundTasks.filter { $0.intent.context.operation == child.target.operation }
        let tasks = related.filter { Optional($0.intent.context.attempt) == child.target.attempt }
        if tasks.isEmpty {
            return child.target.attempt == nil && related.isEmpty ? .notRequired : .unknown
        }
        var requested = false
        for task in tasks {
            let context = task.intent.context
            guard context.storeIdentity == identity,
                  MediaPersonControlValueValidation.exact(context.operation, child.target.operation),
                  MediaPersonControlValueValidation.exact(context.target, child.target.target),
                  MediaPersonControlValueValidation.exact(context.registration, child.target.registration),
                  MediaPersonControlValueValidation.exact(Optional(context.attempt), child.target.attempt),
                  let binding = task.binding, MediaPersonControlValueValidation.exact(binding.session, task.intent.session),
                  binding.taskDescription.utf8.elementsEqual(task.intent.taskDescription.utf8) else { return .unknown }
            if task.terminal != nil { continue } // Only the event consumer may close the owner.
            guard starts[task.intent.id] == nil, preparing[task.intent.id] == nil,
                  let upload = task.intent.source.uploadOwnership,
                  let liveKey = live.keys.first(where: { $0 == task.intent.id }),
                  MediaPersonControlValueValidation.exact(liveKey, task.intent.id),
                  let owned = live[liveKey], !owned.released, !task.events.isEmpty,
                  MediaPersonControlValueValidation.exact(owned.lease, upload.originalLease),
                  MediaPersonControlValueValidation.exact(owned.identity, upload.source),
                  MediaPersonControlValueValidation.exact(owned.binding, Optional(binding)),
                  let session = sessions[task.intent.session], !session.corruptSequence,
                  session.recovery != nil, !session.unsafeIntents.contains(task.intent.id),
                  !retainedEvents.contains(where: { $0.session == task.intent.session }) else { return .unknown }
            for event in task.events {
                guard case .committed(let receipt) = await store.lookupCommit(event.mutation),
                      MediaPersonControlValueValidation.exact(receipt, event.commit),
                      await currentPersonRequest(child, plan: plan) != nil else { return .unknown }
            }
            guard case .succeeded(let observations) = await session.port.enumerate(),
                  let fresh = await currentPersonRequest(child, plan: plan),
                  let request = fresh.requests.first(where: { MediaPersonControlValueValidation.exact($0.operation, child.target.operation) }),
                  MediaPersonControlValueValidation.exact(request.session, Optional(upload.macSession)),
                  knownEnumeration(observations, session: task.intent.session, snapshot: fresh),
                  observations.filter({ $0.taskIdentifier == binding.taskIdentifier
                      && $0.kind == .upload && [.running, .suspended, .canceling].contains($0.state)
                      && MediaPersonControlValueValidation.exact($0.session, binding.session)
                      && binding.taskDescription.utf8.elementsEqual(($0.taskDescription ?? "").utf8) }).count == 1 else { return .unknown }
            switch await session.port.observeTerminal(binding) {
            case .succeeded(let terminal):
                guard MediaPersonControlValueValidation.exact(terminal.binding, binding) else { return .unknown }
                continue
            case .inProgress: break
            default: return .unknown
            }
            guard await currentPersonRequest(child, plan: plan) != nil else { return .unknown }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard let key = try? encoder.encode(binding) else { return .unknown }
            let work: Task<Bool, Never>
            if let existing = personBindingStops[key] { work = existing }
            else {
                work = Task {
                    guard await self.persist(.backgroundTask(command: self.command(), value: .stopRequested(task.intent))),
                          await self.currentPersonRequest(child, plan: plan) != nil else { return false }
                    await session.port.requestStop(binding)
                    return true
                }
                personBindingStops[key] = work
            }
            guard await work.value else { return .unknown }
            requested = true
        }
        return requested ? .requested : .notRequested
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
        if case .uploadChunk = state.intent.source {
            guard let upload = state.intent.source.uploadOwnership, let removalStore,
                  let request = snapshot.requests.first(where: { $0.operation == context.operation }),
                  UploadMetadataValidation.exact(request.operation, context.operation),
                  UploadMetadataValidation.exact(request.target, context.target),
                  UploadMetadataValidation.exact(request.registration, context.registration),
                  UploadMetadataValidation.exact(request.session, Optional(upload.macSession)),
                  (request.attempt != context.attempt || UploadMetadataValidation.exact(request.attempt, Optional(context.attempt))),
                  (request.attempt != context.attempt || request.transport == .stopped),
                  case .succeeded(let inventory) = await removalStore.loadRemovalTransportInventory(context.target.original),
                  inventory.matchesProjection(snapshot),
                  (try? BackgroundUploadChunkAdmission.stoppedRevision(state, journal: inventory.journal, through: snapshot.revision)) != nil,
                  await confirms(state) else { return false }
            for fact in inventory.journal {
                guard case .committed(let receipt) = await store.lookupCommit(fact.mutation),
                      UploadMetadataValidation.exact(receipt, fact.commit) else { return false }
            }
            guard case .succeeded(let originals) = await removalStore.loadOriginalState(), originals.revision == snapshot.revision,
                  let original = originals.logicalOriginals.first(where: { UploadMetadataValidation.exact($0.original, context.target.original) }),
                  !original.readers.contains(where: { $0.id == upload.originalLease.id }),
                  let latest = await load(), latest.revision == snapshot.revision else { return false }
            return true
        }
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

    /// Only the actual writer reservation can ask this process's known upload
    /// owners to stop. Cancellation is not an invalidation/ACK completion.
    func stopForInvalidation(_ record: InvalidationRecord, epoch: ReaderReconciliationEpoch)
        async -> BackendOutcome<BackgroundInvalidationObservation> {
        guard await currentInvalidation(record, epoch: epoch) != nil else { return .unknown }
        await retryHeldEvents()
        guard let snapshot = await currentInvalidation(record, epoch: epoch) else { return .unknown }
        let original = record.rendition.original
        guard !starts.values.contains(where: { $0.original == original }),
              !preparing.keys.contains(where: { live[$0]?.lease.original == original }) else { return .unknown }
        let tasks = snapshot.backgroundTasks.filter { $0.intent.context.target.original == original }
        guard tasks.allSatisfy({ validInvalidationUpload($0, record: record, snapshot: snapshot) }),
              live.allSatisfy({ id, owned in
                  owned.lease.original != original || tasks.contains(where: { PublicationStoreBoundary.exact($0.intent.id, id) })
              }) else { return .unknown }
        var waiting = false
        for task in tasks {
            guard validInvalidationUpload(task, record: record, snapshot: snapshot),
                  let binding = task.binding else { return .unknown }
            // A completely closed old upload is observable from its exact
            // journal and a fresh SDK inventory. No old source is reopened,
            // adopted or released to obtain that observation.
            guard let owned = live[task.intent.id] else { continue }
            if owned.released { continue }
            waiting = true
            // The serial event consumer alone closes a source after a terminal.
            // A recorded/observed terminal must never be replaced by a new SDK
            // request, a synthetic closure, or an adopted old lease.
            if task.terminal != nil || observedTerminals.contains(where: { PublicationStoreBoundary.exact($0, binding) }) { continue }
            guard let session = sessions[task.intent.session], !session.corruptSequence, session.recovery != nil,
                  !session.unsafeIntents.contains(task.intent.id),
                  !retainedEvents.contains(where: { PublicationStoreBoundary.exact($0.session, task.intent.session) }),
                  case .succeeded(let observed) = await session.port.enumerate(),
                  let fresh = await currentInvalidation(record, epoch: epoch),
                  validInvalidationUpload(task, record: record, snapshot: fresh),
                  knownEnumeration(observed, session: task.intent.session, snapshot: fresh),
                  observed.filter({ observation in
                      observation.taskIdentifier == binding.taskIdentifier
                          && PublicationStoreBoundary.exact(observation.session, binding.session)
                          && binding.taskDescription.utf8.elementsEqual((observation.taskDescription ?? "").utf8)
                          && observation.kind == .upload
                          && [.running, .suspended, .canceling].contains(observation.state)
                  }).count == 1 else { return .unknown }
            let terminal = await session.port.observeTerminal(binding)
            guard let fresh = await currentInvalidation(record, epoch: epoch),
                  validInvalidationUpload(task, record: record, snapshot: fresh) else { return .unknown }
            switch terminal {
            case .succeeded(let actual):
                guard PublicationStoreBoundary.exact(actual.binding, binding) else { return .unknown }
                continue
            case .inProgress: break
            default: return .unknown
            }
            if invalidationStops.contains(where: {
                PublicationStoreBoundary.exact($0.record, record) && PublicationStoreBoundary.exact($0.epoch, epoch)
                    && PublicationStoreBoundary.exact($0.binding, binding)
            }) { continue }
            guard await confirmsInvalidationTask(task, record: record, epoch: epoch),
                  await stop(task.intent, binding: binding, session: session.port, invalidation: record, epoch: epoch) else { return .unknown }
        }
        // Even an immediate callback cannot turn the cancellation poll into an
        // ACK. The next explicit poll obtains a new OS/journal inventory.
        if waiting { return .inProgress }
        return await observeInvalidation(record, epoch: epoch)
    }

    func observeInvalidation(_ record: InvalidationRecord, epoch: ReaderReconciliationEpoch)
        async -> BackendOutcome<BackgroundInvalidationObservation> {
        guard await currentInvalidation(record, epoch: epoch) != nil,
              case .succeeded(let transport) = await observeStoppedTransport(record.rendition.original,
                invalidation: record, epoch: epoch),
              let snapshot = await currentInvalidation(record, epoch: epoch) else { return .unknown }
        let value = BackgroundInvalidationObservation(record: record, storeIdentity: identity, transport: transport)
        return value.validates(record: record, epoch: epoch, backend: snapshot) ? .succeeded(value) : .unknown
    }

    private func currentInvalidation(_ record: InvalidationRecord, epoch: ReaderReconciliationEpoch) async -> BackendStoreSnapshot? {
        guard let removalStore, !Task.isCancelled else { return nil }
        for _ in 0..<3 {
            guard let backend = await load(), case .succeeded(let originals) = await removalStore.loadOriginalState() else { return nil }
            if backend.revision != originals.revision { continue }
            let original = record.rendition.original
            guard PublicationStoreBoundary.exact(originals.reconciliationEpoch, Optional(epoch)),
                  let state = originals.logicalOriginals.first(where: { PublicationStoreBoundary.exact($0.original, original) }),
                  !originals.logicalOriginals.contains(where: {
                      $0.original.capture == original.capture && !PublicationStoreBoundary.exact($0.original, original)
                  }), state.removal == nil,
                  state.invalidation.map({ PublicationStoreBoundary.exact($0.record, record) }) == true,
                  let registration = backend.registrations.last(where: {
                      $0.server.registration.destination == record.registration.destination
                  }), registration.isCommitted, PublicationStoreBoundary.exact(registration.server.registration, record.registration),
                  backend.confirmationStates.contains(where: {
                      PublicationStoreBoundary.exact($0.registration, record.registration)
                          && PublicationStoreBoundary.exact($0.current, record.rendition)
                          && $0.generation.rawValue < record.generation.rawValue
                  }) else { return nil }
            return backend
        }
        return nil
    }

    private func invalidationCurrent(_ record: InvalidationRecord?, epoch: ReaderReconciliationEpoch?) async -> Bool {
        guard let record else { return true } // Existing removal observer has no invalidation contract.
        guard let epoch else { return false }
        return await currentInvalidation(record, epoch: epoch) != nil
    }

    private func confirmsInvalidationTask(_ task: BackgroundMediaTaskState, record: InvalidationRecord,
                                         epoch: ReaderReconciliationEpoch) async -> Bool {
        guard !task.events.isEmpty else { return false }
        for event in task.events {
            guard case .committed(let receipt) = await store.lookupCommit(event.mutation),
                  PublicationStoreBoundary.exact(receipt, event.commit),
                  await currentInvalidation(record, epoch: epoch) != nil else { return false }
        }
        return true
    }

    private func validInvalidationUpload(_ task: BackgroundMediaTaskState, record: InvalidationRecord,
        snapshot: BackendStoreSnapshot) -> Bool {
        let context = task.intent.context
        guard context.storeIdentity == identity,
              PublicationStoreBoundary.exact(context.target, MediaTarget.original(record.rendition.original)),
              snapshot.backgroundTasks.contains(where: { PublicationStoreBoundary.exact($0.intent, task.intent) }),
              let binding = task.binding,
              PublicationStoreBoundary.exact(binding.session, task.intent.session),
              binding.taskDescription.utf8.elementsEqual(task.intent.taskDescription.utf8),
              let upload = task.intent.source.uploadOwnership, (try? task.intent.validate()) != nil,
              PublicationStoreBoundary.exact(upload.originalLease.original, record.rendition.original),
              PublicationStoreBoundary.exact(upload.originalLease.operation, context.operation),
              let request = snapshot.requests.first(where: { $0.operation == context.operation }),
              PublicationStoreBoundary.exact(request.operation, context.operation),
              PublicationStoreBoundary.exact(request.registration, context.registration),
              PublicationStoreBoundary.exact(request.target, context.target),
              PublicationStoreBoundary.exact(request.session, Optional(upload.macSession)), request.purpose == .upload,
              request.transport != .completed else { return false }
        let currentAttempt = PublicationStoreBoundary.exact(request.attempt, Optional(context.attempt))
        if upload.descriptor == nil {
            guard currentAttempt, PublicationStoreBoundary.exact(upload.source.content, record.rendition.original.content) else { return false }
        }
        if let key = live.keys.first(where: { $0 == task.intent.id }), let owned = live[key] {
            guard PublicationStoreBoundary.exact(key, task.intent.id),
                  PublicationStoreBoundary.exact(owned.binding, Optional(binding)),
                  PublicationStoreBoundary.exact(owned.lease, upload.originalLease), PublicationStoreBoundary.exact(owned.identity, upload.source) else { return false }
            if !owned.released {
                // OriginalReadLease.epoch belongs to ManagedOriginalAccess,
                // independently of the writer's media reconciliation epoch.
                // currentInvalidation checks that writer epoch; this process's
                // exact live lease/source/binding above proves original ownership.
                return currentAttempt && PublicationStoreBoundary.exact(context.registration, record.registration)
            }
        }
        guard let terminal = task.terminal, let closed = task.ownerClosure,
              PublicationStoreBoundary.exact(terminal.binding, binding), PublicationStoreBoundary.exact(closed.binding, binding),
              PublicationStoreBoundary.exact(closed.uploadSource, Optional(upload.source)), closed.tasksJoined, closed.handlesClosed,
              (!currentAttempt && upload.descriptor != nil) || request.transport == .stopped else { return false }
        // This is only a candidate for the shared observer below. That observer
        // verifies every historical commit, stopped-after-ownerClosed ordering,
        // fresh SDK tasks, current inventory epoch and exact lease absence.
        return true
    }

    private func knownEnumeration(_ observations: [BackgroundMediaTaskObservation], session: BackgroundMediaSessionIdentity,
                                  snapshot: BackendStoreSnapshot) -> Bool {
        guard observations.allSatisfy({ PublicationStoreBoundary.exact($0.session, session) }),
              Set(observations.map(\.taskIdentifier)).count == observations.count else { return false }
        return observations.allSatisfy { observation in
            let matches = snapshot.backgroundTasks.filter {
                guard let binding = $0.binding else { return false }
                return PublicationStoreBoundary.exact(binding.session, observation.session)
                    && binding.taskIdentifier == observation.taskIdentifier
                    && binding.taskDescription.utf8.elementsEqual((observation.taskDescription ?? "").utf8)
            }
            guard matches.count == 1, let matched = matches.first else { return false }
            switch matched.intent.source { case .upload, .uploadChunk: return observation.kind == .upload; case .download: return observation.kind == .download }
        }
    }

    /// Observation only: never request cancellation, adopt an old source or
    /// manufacture a stopped transition in order to satisfy a removal.
    func sealForRemoval(_ seal: OriginalRemovalAdmissionSeal) async -> BackendOutcome<OriginalRemovalTransportFence> {
        if let existing = removalSeals[seal.target.operation], !existing.exactlyMatches(seal) { return .unknown }
        guard !removalSeals.values.contains(where: {
            $0.target.original == seal.target.original && $0.target.operation != seal.target.operation
        }) else { return .notExecuted }
        removalSeals[seal.target.operation] = seal
        guard case .succeeded(let observed) = await observeStoppedTransport(seal.target.original), let snapshot = await load() else { return .unknown }
        let fence = OriginalRemovalTransportFence(seal: seal, inventory: observed.inventory, stops: observed.stops)
        return fence.validatesHistory(snapshot) ? .succeeded(fence) : .unknown
    }

    /// Common no-seal observer. Removal preserves its own real seal/fence;
    /// invalidation supplies its independently persisted reservation instead.
    private func observeStoppedTransport(_ original: OriginalContent, invalidation: InvalidationRecord? = nil,
        epoch: ReaderReconciliationEpoch? = nil) async -> BackendOutcome<BackgroundStoppedTransportObservation> {
        guard let removalStore,
              !starts.values.contains(where: { $0.original == original }),
              !preparing.keys.contains(where: { live[$0]?.lease.original == original }),
              !live.values.contains(where: { $0.lease.original == original && (!$0.released || $0.binding == nil) }),
              case .succeeded(let inventory) = await removalStore.loadRemovalTransportInventory(original),
              await invalidationCurrent(invalidation, epoch: epoch),
              let snapshot = await load(), inventory.matchesProjection(snapshot),
              await invalidationCurrent(invalidation, epoch: epoch) else { return .unknown }
        let stops: [TransportStopReceipt]
        if let historical = OriginalRemovalTransportHistory.stoppedTasks(original, backend: snapshot) { stops = historical }
        else if OriginalRemovalTransportHistory.neverStartedForRemoval(original, backend: snapshot),
                !snapshot.backgroundTasks.contains(where: { $0.intent.context.target.original == original }),
                snapshot.requests.filter({ $0.target.original == original }).allSatisfy({
                    $0.attempt == nil && $0.session == nil && $0.transport == .queued
                }) { stops = [] }
        else { return .unknown }
        let observation = BackgroundStoppedTransportObservation(inventory: inventory, stops: stops)
        guard observation.validatesHistory(snapshot) else { return .unknown }
        for task in inventory.tasks {
            guard await confirmsHistoricalStop(task, snapshot: snapshot), await invalidationCurrent(invalidation, epoch: epoch) else { return .unknown }
            if let invalidation {
                guard epoch != nil, validInvalidationUpload(task, record: invalidation, snapshot: snapshot) else { return .unknown }
            }
            if let owned = live[task.intent.id] {
                guard owned.released, let binding = task.binding,
                      PublicationStoreBoundary.exact(owned.binding, Optional(binding)),
                      let upload = task.intent.source.uploadOwnership,
                      PublicationStoreBoundary.exact(owned.lease, upload.originalLease), PublicationStoreBoundary.exact(owned.identity, upload.source) else { return .unknown }
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
                  await invalidationCurrent(invalidation, epoch: epoch),
                  sessions[sessionIdentity]?.corruptSequence == false,
                  sessions[sessionIdentity]?.recovery != nil,
                  !(sessions[sessionIdentity]?.unsafeIntents.contains(where: { id in
                      inventory.tasks.contains { $0.intent.id == id }
                  }) ?? true),
                  !retainedEvents.contains(where: { $0.session == sessionIdentity }),
                  case .succeeded(let observed) = await port.enumerate(),
                  await invalidationCurrent(invalidation, epoch: epoch) else { return .unknown }
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
                switch matched.intent.source { case .upload, .uploadChunk: kind = .upload; case .download: kind = .download }
                guard observation.kind == kind else { return .unknown }
                if matched.intent.context.target.original == original {
                    guard observation.state == .completed else { return .unknown }
                }
            }
        }
        for fact in inventory.journal {
            guard case .committed(let receipt) = await store.lookupCommit(fact.mutation),
                  PublicationStoreBoundary.exact(receipt, fact.commit),
                  await invalidationCurrent(invalidation, epoch: epoch) else { return .unknown }
        }
        guard !starts.values.contains(where: { $0.original == original }),
              case .succeeded(let latest) = await removalStore.loadRemovalTransportInventory(original), latest == inventory,
              await invalidationCurrent(invalidation, epoch: epoch),
              case .succeeded(let originals) = await removalStore.loadOriginalState(), originals.reconciliationEpoch == inventory.epoch,
              let state = originals.logicalOriginals.first(where: { PublicationStoreBoundary.exact($0.original, original) }),
              inventory.tasks.allSatisfy({ task in
                  if let upload = task.intent.source.uploadOwnership {
                      if upload.descriptor == nil { return !state.readers.contains(upload.originalLease) }
                      return !state.readers.contains(where: { $0.id == upload.originalLease.id })
                  }
                  return false
              }) else { return .unknown }
        guard await invalidationCurrent(invalidation, epoch: epoch) else { return .unknown }
        return .succeeded(observation)
    }

    func releaseAfterRemoval(_ release: OriginalRemovalAdmissionRelease) async -> Bool {
        guard let seal = removalSeals[release.seal.target.operation], seal.exactlyMatches(release.seal),
              case .succeeded = await sealForRemoval(seal), let removalStore,
              case .succeeded(let snapshot) = await removalStore.loadOriginalState(), release.validates(snapshot) else { return false }
        removalSeals.removeValue(forKey: seal.target.operation)
        return true
    }

    @discardableResult private func stop(_ intent: BackgroundMediaTaskIntent, binding: BackgroundMediaTaskBinding,
                      session: any BackgroundMediaSessionPort, invalidation: InvalidationRecord? = nil,
                      epoch: ReaderReconciliationEpoch? = nil) async -> Bool {
        guard await persist(.backgroundTask(command: command(), value: .stopRequested(intent))) else { return false }
        if let invalidation {
            guard let epoch, let snapshot = await currentInvalidation(invalidation, epoch: epoch),
                  let task = snapshot.backgroundTasks.first(where: { PublicationStoreBoundary.exact($0.intent, intent) }),
                  PublicationStoreBoundary.exact(task.binding, Optional(binding)),
                  validInvalidationUpload(task, record: invalidation, snapshot: snapshot),
                  live[task.intent.id]?.released == false else { return false }
            invalidationStops.append(.init(record: invalidation, epoch: epoch, binding: binding))
        }
        await session.requestStop(binding)
        return await invalidationCurrent(invalidation, epoch: epoch)
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
        case .downloadArtifactUnavailable, .downloadArtifact:
            // A retains the opaque same-owner artifact for the future import
            // consumer. Never await a later terminal inside this serial event.
            // Finish-events acknowledge delivery, not FD/worker/lease drain.
            retainedEvents.append(event)
            return true
        case .taskTerminal(let terminal): return await processTerminal(terminal, event: event)
        case .unknownTaskTerminal(let observation, let outcome):
            guard let snapshot = await load() else { return false }
            let matches = snapshot.backgroundTasks.filter {
                guard let binding = $0.binding else { return false }
                let expected: BackgroundMediaTaskKind
                switch $0.intent.source { case .upload, .uploadChunk: expected = .upload; case .download: expected = .download }
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
            guard case .succeeded(let receipt) = await originals.releaseRead(owned.lease) else { return false }
            if case .uploadChunk = state.intent.source {
                guard UploadMetadataValidation.exact(receipt.lease, owned.lease) else { return false }
            } else { guard receipt.lease == owned.lease else { return false } }
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
        let current: Bool
        if case .uploadChunk = state.intent.source {
            current = UploadMetadataValidation.exact(request.attempt, Optional(context.attempt))
                && UploadMetadataValidation.exact(request.target, context.target)
                && UploadMetadataValidation.exact(request.registration, context.registration) && request.transport != .completed
        } else {
            current = request.attempt == context.attempt && request.target == context.target
                && request.registration == context.registration && request.transport != .completed
        }
        guard current else {
            if case .uploadChunk = state.intent.source {
                guard let actual = latest.backgroundTasks.first(where: { UploadMetadataValidation.exact($0.intent, state.intent) }),
                      await confirmsHistoricalStop(actual, snapshot: latest) else { return false }
            }
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
            guard case .committed(let receipt) = await store.lookupCommit(event.mutation),
                  UploadMetadataValidation.exact(receipt, event.commit) else { return false }
        }
        return true
    }

    /// Lost replies are reconciled with the exact retained mutation. A new CAS
    /// revision is used only after a definite revision-conflict rejection.
    private func persist(_ requested: BackendStoreChange) async -> Bool {
        if case .backgroundTask(_, let value) = requested, let state = await state(value.intent.id),
           let stored = state.events.first(where: { sameBackgroundChange($0.change, value) }) {
            guard case .committed(let receipt) = await store.lookupCommit(stored.mutation), receipt == stored.commit else { return false }
            return true
        }
        if let retained = pending.first(where: { mutation in
            if case .backgroundTask(_, let lhs) = mutation.change, case .backgroundTask(_, let rhs) = requested { return sameBackgroundChange(lhs, rhs) }
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

    private func sameBackgroundChange(_ lhs: BackgroundMediaTaskChange, _ rhs: BackgroundMediaTaskChange) -> Bool {
        switch (lhs.intent.source, rhs.intent.source) {
        case (.uploadChunk, _), (_, .uploadChunk): UploadMetadataValidation.exact(lhs, rhs)
        default: lhs == rhs
        }
    }

    private func command() -> MediaOperationID { .init(rawValue: "background-" + UUID().uuidString) }
}
