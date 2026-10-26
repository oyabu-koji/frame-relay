import Foundation

/// One immutable query precedes each HTTP exchange. Local commit uncertainty
/// is reconciled before another query; neither restoration nor lookup dispatches.
actor UploadMetadataCoordinator: UploadMetadataPort {
    private enum Mode: Equatable { case explicit, knownSession, reconcile }
    private struct Active {
        let request: UploadMetadataRequest
        let nonce: UUID
        let task: Task<UploadMetadataResult, Never>
    }
    private let store: any MediaOperationStorePort
    private let remote: any UploadMetadataRemotePort
    private let admission: @MainActor @Sendable () -> Bool
    private let didChange: @Sendable () async -> Void
    private var active: [String: Active] = [:]
    private var pending: [String: BackendStoreMutation] = [:]
    private var ready: [String: UploadMetadataObservation] = [:]
    private var notified: Set<MediaOperationID> = []

    init(store: any MediaOperationStorePort, remote: any UploadMetadataRemotePort,
         admission: @escaping @MainActor @Sendable () -> Bool = { true },
         didChange: @escaping @Sendable () async -> Void = {}) {
        self.store = store; self.remote = remote; self.admission = admission; self.didChange = didChange
    }
    func refresh(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await run(request, mode: .explicit) }
    func refreshKnownSession(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await run(request, mode: .knownSession) }
    func reconcilePending(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await run(request, mode: .reconcile) }

    private func run(_ request: UploadMetadataRequest, mode: Mode) async -> UploadMetadataResult {
        do { try request.validate() } catch { return .rejected(.invalidValue) }
        let key = Self.key(request)
        if let old = active[key] {
            guard UploadMetadataValidation.exact(old.request, request) else { return .rejected(.identityMismatch) }
            return await old.task.value
        }
        let nonce = UUID(), task = Task { await self.drive(request, mode: mode) }
        active[key] = .init(request: request, nonce: nonce, task: task)
        let result = await task.value
        if active[key]?.nonce == nonce { active.removeValue(forKey: key) }
        return result
    }

    private func drive(_ request: UploadMetadataRequest, mode: Mode) async -> UploadMetadataResult {
        let key = Self.key(request)
        if let mutation = pending[key] {
            guard Self.matches(mutation, request) else { return .rejected(.identityMismatch) }
            return await reconcile(mutation, request: request)
        }
        if mode == .reconcile {
            guard let snapshot = try? await UploadMetadataScope.historical(store, request: request),
                  let query = snapshot.uploadMetadataQueries.last(where: {
                      $0.isCommitted && UploadMetadataValidation.exact($0.query.request, request)
                  }) else { return .unknown }
            if let record = snapshot.uploadMetadataObservations.last(where: {
                UploadMetadataValidation.exact($0.observation.query, query)
            }) {
                pending[key] = record.mutation
                return await reconcile(record.mutation, request: request)
            }
            // A reopened unobserved reservation has no live HTTP capability.
            pending[key] = query.mutation
            return await reconcile(query.mutation, request: request)
        }
        if let observation = ready[key] {
            guard UploadMetadataValidation.exact(observation.query.query.request, request) else { return .rejected(.identityMismatch) }
            return await persist(observation, request: request)
        }
        guard await admission(), !Task.isCancelled else { return .rejected(.unavailable) }
        let queryID = MediaOperationID(rawValue: UUID().uuidString.lowercased())
        let observationID = MediaOperationID(rawValue: UUID().uuidString.lowercased())
        for _ in 0..<3 {
            let snapshot: BackendStoreSnapshot, current: MediaRequest
            do {
                snapshot = try await UploadMetadataScope.current(store, request: request)
                current = try UploadMetadataScope.request(request, in: snapshot)
            } catch let error as BackendContractError { return .rejected(error) }
            catch { return .rejected(.unavailable) }
            let kind: UploadMetadataQueryKind
            if let session = current.session { kind = .lookup(session) }
            else {
                guard mode == .explicit, current.intent == .running, current.transport != .completed,
                      !current.playbackEnded, current.uploadMetadataHold == nil else { return .rejected(.wrongStage) }
                if case .succeeded = current.remote { return .rejected(.wrongStage) }
                kind = .create
            }
            let query: UploadMetadataQuery
            do {
                let reservations = snapshot.uploadMetadataQueries.filter {
                    UploadMetadataValidation.exact($0.query.request.operation, request.operation)
                }.map { $0.query.generation }
                query = try .init(id: queryID, observationCommand: observationID, request: request, kind: kind,
                    generation: UploadMetadataGeneration.next(lastObservation: current.lastObservation, reservations: reservations))
            } catch let error as BackendContractError { return .rejected(error) }
            catch { return .rejected(.invalidValue) }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: .uploadMetadata(.beginQuery(query)),
                expectedStoreIdentity: request.storeIdentity)
            pending[key] = mutation
            switch await store.commit(mutation) {
            case .rejected(.revisionConflict): pending.removeValue(forKey: key); continue
            case .rejected(let error): pending.removeValue(forKey: key); return .rejected(error)
            case .unknown, .unavailable:
                // Even an immediately recovered begin ends this call without HTTP.
                return await reconcile(mutation, request: request)
            case .committed:
                guard let committed = await confirmBegin(mutation, request: request) else { return .unknown }
                pending.removeValue(forKey: key)
                guard await admission(), !Task.isCancelled else { return .rejected(.unavailable) }
                do { _ = try await UploadMetadataScope.dispatch(store, query: committed) }
                catch let error as BackendContractError { return .rejected(error) }
                catch { return .rejected(.unavailable) }
                let result: BackendOutcome<UploadMetadataResponse>
                switch kind {
                case .create: result = await remote.create(committed)
                case .lookup: result = await remote.lookup(committed)
                }
                guard case .succeeded(let response) = result else {
                    if case .notExecuted = result { return .rejected(.wrongStage) }
                    return .unknown
                }
                let observation: UploadMetadataObservation
                do { observation = try .init(command: observationID, query: committed, response: response) }
                catch { return .rejected(.identityMismatch) }
                ready[key] = observation
                return await persist(observation, request: request)
            }
        }
        return .rejected(.revisionConflict)
    }

    private func persist(_ observation: UploadMetadataObservation, request: UploadMetadataRequest) async -> UploadMetadataResult {
        let key = Self.key(request)
        for _ in 0..<3 {
            let snapshot: BackendStoreSnapshot
            do { snapshot = try await UploadMetadataScope.current(store, request: request) }
            catch let error as BackendContractError { ready.removeValue(forKey: key); return .rejected(error) }
            catch { return .rejected(.unavailable) }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: .uploadMetadata(.observe(observation)),
                expectedStoreIdentity: request.storeIdentity)
            pending[key] = mutation
            switch await store.commit(mutation) {
            case .rejected(.revisionConflict): pending.removeValue(forKey: key); continue
            case .rejected(let error): pending.removeValue(forKey: key); ready.removeValue(forKey: key); return .rejected(error)
            case .committed, .unknown, .unavailable: return await reconcile(mutation, request: request)
            }
        }
        // The response remains a known proposal for a later explicit local
        // save retry, but no uncertain envelope or automatic HTTP retry remains.
        return .rejected(.revisionConflict)
    }

    private func confirmBegin(_ mutation: BackendStoreMutation, request: UploadMetadataRequest) async -> CommittedUploadMetadataQuery? {
        guard case .uploadMetadata(.beginQuery(let query)) = mutation.change,
              case .committed(let receipt) = await store.lookupCommit(mutation),
              receipt.matches(query.key, revision: mutation.expectedRevision), UploadMetadataValidation.exact(receipt.key, query.key),
              let snapshot = try? await UploadMetadataScope.historical(store, request: request),
              let saved = snapshot.uploadMetadataQueries.first(where: { UploadMetadataValidation.exact($0.query, query) }),
              saved.isCommitted, UploadMetadataValidation.exact(saved.commit, receipt),
              UploadMetadataValidation.exact(saved.mutation, mutation) else { return nil }
        return saved
    }

    private func confirmObservation(_ mutation: BackendStoreMutation, request: UploadMetadataRequest) async -> StoredUploadMetadataObservation? {
        guard case .uploadMetadata(.observe(let observation)) = mutation.change,
              case .committed(let receipt) = await store.lookupCommit(mutation),
              receipt.matches(observation.key, revision: mutation.expectedRevision), UploadMetadataValidation.exact(receipt.key, observation.key),
              let snapshot = try? await UploadMetadataScope.historical(store, request: request),
              let record = snapshot.uploadMetadataObservations.first(where: { UploadMetadataValidation.exact($0.observation, observation) }),
              record.isCommitted, UploadMetadataValidation.exact(record.commit, receipt),
              UploadMetadataValidation.exact(record.mutation, mutation) else { return nil }
        return record
    }

    private func reconcile(_ mutation: BackendStoreMutation, request: UploadMetadataRequest) async -> UploadMetadataResult {
        let key = Self.key(request)
        switch mutation.change {
        case .uploadMetadata(.beginQuery(let query)):
            guard let before = await confirmBegin(mutation, request: request) else { return .unknown }
            if notified.insert(query.id).inserted { await didChange() }
            guard let after = await confirmBegin(mutation, request: request), UploadMetadataValidation.exact(after, before) else { return .unknown }
            pending.removeValue(forKey: key)
            return .unknown
        case .uploadMetadata(.observe(let observation)):
            guard let before = await confirmObservation(mutation, request: request) else { return .unknown }
            if notified.insert(observation.command).inserted { await didChange() }
            guard let after = await confirmObservation(mutation, request: request), UploadMetadataValidation.exact(after, before) else { return .unknown }
            pending.removeValue(forKey: key); ready.removeValue(forKey: key)
            return .recorded(after)
        default: return .rejected(.identityMismatch)
        }
    }
    private static func matches(_ mutation: BackendStoreMutation, _ request: UploadMetadataRequest) -> Bool {
        guard case .uploadMetadata(let value) = mutation.change else { return false }
        return mutation.expectedStoreIdentity == request.storeIdentity && UploadMetadataValidation.exact(value.request, request)
    }
    private static func key(_ request: UploadMetadataRequest) -> String {
        request.storeIdentity.rawValue.uuidString + ":" + Data(request.operation.rawValue.utf8).base64EncodedString()
    }
}

nonisolated enum UploadMetadataScope {
    static func historical(_ store: any MediaOperationStorePort, request: UploadMetadataRequest) async throws -> BackendStoreSnapshot {
        guard case .loaded(let snapshot) = await store.load() else { throw BackendContractError.unavailable }
        guard snapshot.storeIdentity == request.storeIdentity else { throw BackendContractError.identityMismatch }
        return snapshot
    }
    static func current(_ store: any MediaOperationStorePort, request: UploadMetadataRequest) async throws -> BackendStoreSnapshot {
        let snapshot = try await StatusSynchronizationRegistrationBoundary(store: store, identity: request.storeIdentity,
            registration: request.registration).load()
        _ = try self.request(request, in: snapshot)
        return snapshot
    }
    static func request(_ request: UploadMetadataRequest, in snapshot: BackendStoreSnapshot) throws -> MediaRequest {
        let rows = snapshot.requests.filter { request.matches($0) }
        guard rows.count == 1 else { throw BackendContractError.identityMismatch }
        return rows[0]
    }
    static func dispatch(_ store: any MediaOperationStorePort, query: CommittedUploadMetadataQuery) async throws -> BackendStoreSnapshot {
        let request = query.query.request, snapshot = try await current(store, request: request)
        guard query.isCommitted, snapshot.uploadMetadataQueries.contains(where: { UploadMetadataValidation.exact($0, query) }),
              !snapshot.uploadMetadataObservations.contains(where: { UploadMetadataValidation.exact($0.observation.query, query) }),
              snapshot.uploadMetadataQueries.filter({ UploadMetadataValidation.exact($0.query.request.operation, request.operation) })
                .map({ $0.query.generation.rawValue }).max() == query.query.generation.rawValue,
              case .committed(let receipt) = await store.lookupCommit(query.mutation), UploadMetadataValidation.exact(receipt, query.commit) else {
            throw BackendContractError.notCommitted
        }
        let fresh = try await current(store, request: request), current = try self.request(request, in: fresh)
        guard current.uploadMetadataPending == query.query.generation else { throw BackendContractError.staleGeneration }
        switch query.query.kind {
        case .create:
            guard current.intent == .running, current.session == nil, current.uploadMetadataHold == nil,
                  current.transport != .completed, !current.playbackEnded else { throw BackendContractError.wrongStage }
            if case .succeeded = current.remote { throw BackendContractError.wrongStage }
        case .lookup(let session):
            guard UploadMetadataValidation.exact(current.session, Optional(session)) else { throw BackendContractError.identityMismatch }
        }
        return fresh
    }
}
