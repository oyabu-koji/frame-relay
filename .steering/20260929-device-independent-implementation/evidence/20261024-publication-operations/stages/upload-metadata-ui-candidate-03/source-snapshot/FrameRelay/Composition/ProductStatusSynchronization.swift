import Foundation

/// App-lifetime owner of the metadata coordinators. Registration restoration
/// and constructing this container perform no request and create no intent.
actor ProductStatusSynchronization: StatusSynchronizationPort {
    typealias RemoteFactory = @Sendable (RegistrationConnection, any RegistrationAuthorizationPort,
        any MediaOperationStorePort, RegistrationStoreIdentity) -> any PublicationRemotePort
    private let store: any MediaOperationStorePort & OriginalStorePort
    private let access: ManagedOriginalAccess
    private let media: ProductMediaTermination
    private let credentials: any RegistrationAuthorizationPort
    private let admission: @MainActor @Sendable () -> Bool
    private let remoteFactory: RemoteFactory
    private let background: (any BackgroundInvalidationTerminationPort)?
    private let uploadMetadata: (any UploadMetadataPort)?
    private var sessions: [Session] = []
    private var running = false

    init(store: any MediaOperationStorePort & OriginalStorePort, access: ManagedOriginalAccess,
         media: ProductMediaTermination, credentials: any RegistrationAuthorizationPort,
         admission: @escaping @MainActor @Sendable () -> Bool,
         background: (any BackgroundInvalidationTerminationPort)? = nil,
         uploadMetadata: (any UploadMetadataPort)? = nil,
         remoteFactory: @escaping RemoteFactory = { connection, credentials, store, identity in
             URLSessionPublicationRemote(connection: connection, credentials: credentials, store: store, identity: identity)
         }) {
        self.store = store; self.access = access; self.media = media; self.credentials = credentials
        self.admission = admission; self.remoteFactory = remoteFactory
        self.background = background
        self.uploadMetadata = uploadMetadata
    }

    func synchronize(connection: RegistrationConnection, registration: DeviceRegistration) async -> StatusSynchronizationReport {
        guard !running else { return .init(phase: .busy) }
        running = true; defer { running = false }
        do {
            guard await admission() else { return .init(phase: .waitingForCapture) }
            guard case .loaded(let initial) = await store.load(), let identity = initial.storeIdentity,
                  PublicationStoreBoundary.exact(connection.destination, registration.server.registration.destination) else {
                return .init(phase: .unavailable)
            }
            let boundary = StatusSynchronizationRegistrationBoundary(store: store, identity: identity, registration: registration)
            let fixed = try await boundary.load()
            let uploads = try fixed.requests.filter { row in
                guard row.purpose == .upload, row.startCommitted, row.session != nil,
                      UploadMetadataValidation.exact(row.registration, registration.server.registration) else { return false }
                if case .original = row.target { return true }; return false
            }.map { row in
                try UploadMetadataRequest(storeIdentity: identity, registration: registration, operation: row.operation,
                    original: row.target.original, expectedStartRevision: row.expectedStartRevision)
            }
            let coordinator: BackendStatusSynchronizationCoordinator
            if let existing = sessions.first(where: {
                $0.identity == identity && PublicationStoreBoundary.exact($0.registration, registration)
                    && PublicationStoreBoundary.exact($0.connection.destination, connection.destination)
                    && $0.connection.endpoint.origin.absoluteString.utf8.elementsEqual(connection.endpoint.origin.absoluteString.utf8)
            }) { coordinator = existing.coordinator }
            else {
                let external = ProductStatusInvalidationTermination(boundary: boundary, originals: store,
                    media: media, admission: admission, background: background)
                let invalidations = MediaInvalidationCoordinator(store: store, identity: identity, ordering: access,
                    scopes: media.scopes, external: external)
                coordinator = BackendStatusSynchronizationCoordinator(store: store, identity: identity, registration: registration,
                    remote: remoteFactory(connection, credentials, store, identity), invalidations: invalidations,
                    admission: admission, didInvalidate: { [media] ack in try await media.resume(after: ack) })
                sessions.append(.init(identity: identity, connection: connection, registration: registration, coordinator: coordinator))
            }
            let result = await coordinator.synchronize()
            _ = try await boundary.load()
            if let uploadMetadata, result.phase == .checked || result.phase == .partial {
                var unresolved = false
                for request in uploads {
                    guard await admission(), !Task.isCancelled else { unresolved = true; break }
                    // Known-session only. This path never retries an unknown
                    // POST or turns a newly received catalog row into a request.
                    let observation = await uploadMetadata.refreshKnownSession(request)
                    _ = try await boundary.load()
                    if case .recorded(let record) = observation, case .status = record.observation.response {} else { unresolved = true }
                }
                if unresolved {
                    return .init(phase: .partial, items: result.items, hasMore: result.hasMore,
                        unresolvedInvalidations: result.unresolvedInvalidations)
                }
            }
            return result
        } catch { return .init(phase: .unavailable) }
    }

    private struct Session {
        let identity: RegistrationStoreIdentity
        let connection: RegistrationConnection
        let registration: DeviceRegistration
        let coordinator: BackendStatusSynchronizationCoordinator
    }
}

/// Combines the actual original player with the same app-lifetime background
/// owner. An old/unknown source or prepared attachment gap stays unresolved.
///
/// The coordinator commits reserveInvalidation BEFORE calling this wrapper.
/// That reservation fences acquire/acquireMedia and background prepared/resume
/// in the same writer. A copy already in flight owns a durable reader lease;
/// an attached task already owns a durable prepared intent. Neither can enter
/// unnoticed between this inventory and the final invalidation commit.
actor ProductStatusInvalidationTermination: PublicationExternalTerminationPort {
    private let boundary: StatusSynchronizationRegistrationBoundary
    private let originals: any OriginalStorePort
    private let media: ProductMediaTermination
    private let admission: @MainActor @Sendable () -> Bool
    private let background: (any BackgroundInvalidationTerminationPort)?
    init(boundary: StatusSynchronizationRegistrationBoundary, originals: any OriginalStorePort, media: ProductMediaTermination,
         admission: @escaping @MainActor @Sendable () -> Bool,
         background: (any BackgroundInvalidationTerminationPort)? = nil) {
        self.boundary = boundary; self.originals = originals; self.media = media; self.admission = admission
        self.background = background
    }
    private func check(_ original: OriginalContent) async throws {
        guard await admission(), !Task.isCancelled else { throw BackendContractError.unavailable }
        let snapshot = try await boundary.load()
        // Conservative equality here also refuses canonically equivalent but
        // byte-distinct historical owners; it never grants an identity match.
        guard !snapshot.backgroundTasks.contains(where: { $0.intent.context.target.original == original }),
              OriginalRemovalTransportHistory.neverStarted(original, backend: snapshot) else {
            throw BackendContractError.readersActive
        }
    }
    func stopAndObserve(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws {
        guard let background else {
            try await check(original)
            try await media.stopAndObserve(original: original, epoch: epoch)
            try await check(original)
            return
        }
        let record = try await reservation(original: original, epoch: epoch).record
        let before = try await backgroundObservation(background, record: record, epoch: epoch, stopping: true)
        try await media.stopAndObserve(original: original, epoch: epoch)
        let after = try await backgroundObservation(background, record: record, epoch: epoch, stopping: false)
        guard before.inventory == after.inventory, PublicationStoreBoundary.exact(before.stops, after.stops) else {
            throw BackendContractError.readersActive
        }
    }
    func observeTerminal(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws -> EvidenceID {
        guard let background else {
            try await check(original)
            let result = try await media.observeTerminal(original: original, epoch: epoch)
            try await check(original)
            return result
        }
        let record = try await reservation(original: original, epoch: epoch).record
        let before = try await backgroundObservation(background, record: record, epoch: epoch, stopping: false)
        let result = try await media.observeTerminal(original: original, epoch: epoch)
        let after = try await backgroundObservation(background, record: record, epoch: epoch, stopping: false)
        guard before.inventory == after.inventory, PublicationStoreBoundary.exact(before.stops, after.stops) else {
            throw BackendContractError.readersActive
        }
        return result
    }

    private func reservation(original: OriginalContent, epoch: ReaderReconciliationEpoch)
        async throws -> (record: InvalidationRecord, backend: BackendStoreSnapshot) {
        for _ in 0..<3 {
            guard await admission(), !Task.isCancelled else { throw BackendContractError.unavailable }
            let backend = try await boundary.load()
            guard case .succeeded(let snapshot) = await originals.loadOriginalState() else { throw BackendContractError.unavailable }
            if backend.revision != snapshot.revision { continue }
            guard PublicationStoreBoundary.exact(snapshot.reconciliationEpoch, Optional(epoch)),
                  let state = snapshot.logicalOriginals.first(where: { PublicationStoreBoundary.exact($0.original, original) }),
                  state.removal == nil, let pending = state.invalidation,
                  PublicationStoreBoundary.exact(pending.rendition.original, original),
                  PublicationStoreBoundary.exact(pending.registration, boundary.registration.server.registration) else {
                throw BackendContractError.identityMismatch
            }
            return (pending.record, backend)
        }
        throw BackendContractError.revisionConflict
    }

    private func backgroundObservation(_ background: any BackgroundInvalidationTerminationPort,
        record: InvalidationRecord, epoch: ReaderReconciliationEpoch, stopping: Bool) async throws -> BackgroundInvalidationObservation {
        let before = try await reservation(original: record.rendition.original, epoch: epoch)
        guard PublicationStoreBoundary.exact(before.record, record) else { throw BackendContractError.identityMismatch }
        let result = stopping ? await background.stopForInvalidation(record, epoch: epoch)
            : await background.observeInvalidation(record, epoch: epoch)
        let after = try await reservation(original: record.rendition.original, epoch: epoch)
        guard PublicationStoreBoundary.exact(after.record, record), case .succeeded(let observation) = result,
              observation.validates(record: record, epoch: epoch, backend: after.backend) else {
            throw BackendContractError.readersActive
        }
        return observation
    }
}
