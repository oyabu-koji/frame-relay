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
actor BackgroundMediaCoordinator {
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
    private let admission: any BackgroundMediaStrictAdmissionPort
    private let makeSession: SessionFactory
    private let makeSource: SourceFactory
    private let didDrain: DidDrain
    private var sessions: [BackgroundMediaSessionIdentity: Session] = [:]
    private var connections: [BackgroundMediaSessionIdentity: Task<any BackgroundMediaSessionPort, Error>] = [:]
    private var consumers: [BackgroundMediaSessionIdentity: Task<Void, Never>] = [:]
    private var live: [BackgroundMediaTaskID: LiveSource] = [:]
    private var preparing: [BackgroundMediaTaskID: BackgroundMediaAttachmentBarrier] = [:]
    private var starts = Set<BackgroundMediaTaskID>()
    private var pending: [BackendStoreMutation] = []
    private var observedTerminals: [BackgroundMediaTaskBinding] = []
    private(set) var retainedEvents: [BackgroundMediaSDKEvent] = []

    init(store: any MediaOperationStorePort, identity: RegistrationStoreIdentity,
         originals: any OriginalAccessPort,
         admission: any BackgroundMediaStrictAdmissionPort = UnavailableBackgroundMediaStrictAdmission(),
         sessionFactory: @escaping SessionFactory, sourceFactory: @escaping SourceFactory,
         didDrain: @escaping DidDrain = { _ in }) {
        self.store = store; self.identity = identity; self.originals = originals; self.admission = admission
        makeSession = sessionFactory; makeSource = sourceFactory; self.didDrain = didDrain
    }

    func startUpload(_ plan: BackgroundMediaUploadPlan) async -> BackgroundMediaStartResult {
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
        guard starts.insert(plan.id).inserted else { return .unknown }
        defer { starts.remove(plan.id) }
        // This guard precedes beginAttempt, lease acquisition, source copy and
        // even the suspended SDK session/task factories in the normal root.
        let permission = await admission.permit(plan.context)
        guard case .succeeded(let permit) = permission else {
            if case .notExecuted = permission { return .refused(.strictAdmissionUnavailable) }
            return .refused(.strictAdmissionRejected)
        }
        guard permit.context == plan.context, !permit.evidence.rawValue.isEmpty else { return .refused(.identityMismatch) }
        guard let current = await load(),
              let request = current.requests.first(where: { $0.operation == plan.context.operation }),
              request.target == plan.context.target, request.registration == plan.context.registration,
              request.purpose == .upload, request.session == plan.macSession, request.canRun else {
            return .refused(.requestNotReady)
        }
        let begin = BackendStoreChange.requestTransition(command: command(), operation: request.operation,
            target: request.target, registration: request.registration, value: .beginAttempt(plan.context.attempt))
        guard await persist(begin) else { return .unknown }
        guard case .succeeded(let lease) = await originals.acquireRead(original, operation: request.operation,
            leaseID: .init(rawValue: UUID().uuidString)) else { return .unknown }
        do {
            let source = try await makeSource()
            let copy = try await source.create(from: lease, id: plan.sourceID)
            live[plan.id] = .init(source: source, identity: copy, lease: lease)
            let intent = BackgroundMediaTaskIntent(id: plan.id, context: plan.context, session: plan.session,
                taskDescription: plan.taskDescription, requestFingerprint: fingerprint,
                source: .upload(session: plan.macSession, lease: lease, source: copy))
            try intent.validate()
            guard await persist(.backgroundTask(command: command(), value: .prepared(intent))) else { return .unknown }
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
        guard case .succeeded(let permit) = await admission.permit(context), permit.context == context else {
            return .refused(.strictAdmissionUnavailable)
        }
        return .refused(.downloadIngressUnavailable)
    }

    private func createAndResume(_ intent: BackgroundMediaTaskIntent, plan: BackgroundMediaUploadPlan,
        source: any BackgroundMediaUploadSourcePort, lease: OriginalReadLease,
        barrier: BackgroundMediaAttachmentBarrier) async -> BackgroundMediaStartResult {
        do {
            guard let owned = live[intent.id] else { return .unknown }
            let file = try await source.uploadFile(for: owned.identity, lease: lease)
            let session = try await session(for: intent.session)
            guard sessions[intent.session]?.recovery != nil else { return .unknown }
            guard case .succeeded(let binding) = await session.createSuspended(intent, request: plan.request, upload: file),
                  binding.session == intent.session, binding.taskDescription == intent.taskDescription,
                  binding.taskIdentifier > 0 else { return .unknown }
            live[intent.id]?.binding = binding
            try await source.retain(file.identity, lease: lease, for: binding)
            guard await persist(.backgroundTask(command: command(), value: .attached(intent, binding))) else { return .unknown }
            await barrier.finish()
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
            guard await persist(.backgroundTask(command: command(), value: .resumeRequested(intent, binding))) else { return .unknown }
            guard case .succeeded(let resumed) = await session.resume(binding, permit: permit), resumed == binding else {
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

    private func stop(_ intent: BackgroundMediaTaskIntent, binding: BackgroundMediaTaskBinding,
                      session: any BackgroundMediaSessionPort) async {
        guard await persist(.backgroundTask(command: command(), value: .stopRequested(intent))) else { return }
        await session.requestStop(binding)
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
        guard state.terminal == nil || state.terminal == terminal,
              await persist(.backgroundTask(command: command(), value: .terminal(state.intent, terminal))) else { return false }
        guard var owned = live[state.intent.id] else {
            // Reopened source/lease adoption is deliberately unavailable. The
            // actual terminal is durable in its old context; unknown owners and
            // readers remain, independent of OS delivery completion.
            return true
        }
        guard owned.binding == terminal.binding else { return false }
        if owned.released { return true }
        do {
            let closed = try await owned.source.finish(owned.identity, lease: owned.lease, terminal: terminal)
            guard closed.binding == terminal.binding, closed.uploadSource == owned.identity,
                  closed.tasksJoined, closed.handlesClosed,
                  await persist(.backgroundTask(command: command(), value: .ownerClosed(state.intent, closed))) else { return false }
            guard case .succeeded(let receipt) = await originals.releaseRead(owned.lease), receipt.lease == owned.lease else { return false }
            owned.released = true
            live[state.intent.id] = owned
            return true
        } catch { return false }
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
