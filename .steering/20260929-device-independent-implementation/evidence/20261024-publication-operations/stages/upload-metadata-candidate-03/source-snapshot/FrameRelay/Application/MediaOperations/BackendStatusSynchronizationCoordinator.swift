import Foundation

/// One registration, one writer, and one retained poll cursor. No media factory
/// is available here. Each explicit call reads at most one invalidation page;
/// the finite original/outbox inventories are fixed before their respective pass.
actor BackendStatusSynchronizationCoordinator {
    private let boundary: StatusSynchronizationRegistrationBoundary
    private let store: any MediaOperationStorePort & OriginalStorePort
    private let remote: StatusSynchronizationRemote
    private let invalidations: MediaInvalidationCoordinator
    private let outbox: BackendOutboxCoordinator
    private let admission: @MainActor @Sendable () -> Bool
    private let didInvalidate: @Sendable (InvalidationAcknowledgement) async throws -> Void
    private var running = false
    private var after: InvalidationID?
    private var unresolved: [InvalidationRecord] = []
    private var pending: [BackendStoreMutation] = []
    private var recoveredAuthorityWithoutManifest = false

    init(store: any MediaOperationStorePort & OriginalStorePort, identity: RegistrationStoreIdentity,
         registration: DeviceRegistration, remote: any PublicationRemotePort,
         invalidations: MediaInvalidationCoordinator,
         admission: @escaping @MainActor @Sendable () -> Bool = { true },
         didInvalidate: @escaping @Sendable (InvalidationAcknowledgement) async throws -> Void = { _ in }) {
        self.store = store; self.invalidations = invalidations; self.admission = admission
        self.didInvalidate = didInvalidate
        let boundary = StatusSynchronizationRegistrationBoundary(store: store, identity: identity, registration: registration)
        self.boundary = boundary
        let guarded = StatusSynchronizationRemote(base: remote, boundary: boundary, admission: admission)
        self.remote = guarded
        outbox = BackendOutboxCoordinator(store: store, identity: identity, remote: guarded)
    }

    func synchronize() async -> StatusSynchronizationReport {
        guard !running else { return .init(phase: .busy) }
        running = true; defer { running = false }
        recoveredAuthorityWithoutManifest = false
        do {
            guard await admission() else { return .init(phase: .waitingForCapture, hasMore: after != nil) }
            _ = try await boundary.load()
            guard case .succeeded(let originals) = await store.loadOriginalState() else { throw BackendContractError.unavailable }
            let backend = try await boundary.load()
            var known: [OriginalContent] = []
            var knownIDs = Set<RemoteInventoryOriginalID>()
            func appendKnown(_ original: OriginalContent) {
                let id = RemoteInventoryOriginalID(destination: boundary.registration.server.registration.destination,
                    original: original)
                if knownIDs.insert(id).inserted { known.append(original) }
            }
            originals.logicalOriginals.forEach { appendKnown($0.original) }
            for page in backend.remoteInventory where page.isCommitted {
                guard page.observation.storeIdentity == boundary.identity,
                      exact(page.observation.registration, boundary.registration.server.registration) else { continue }
                page.observation.page.originals.forEach(appendKnown)
            }
            for state in originals.logicalOriginals {
                if let reservation = state.invalidation { retain(reservation.record) }
            }
            var partial = false
            let page = await remote.invalidations(registration: boundary.registration.server.registration, after: after)
            _ = try await boundary.load()
            if case .succeeded(let value) = page, valid(value, after: after) {
                value.records.forEach { retain($0) }
                after = value.nextAfter
            } else { partial = true }

            // Keep unresolved records independently of pagination. A failure on
            // an earlier page cannot disappear when a later page is requested.
            let attempts = unresolved
            for record in attempts {
                guard await admission() else { partial = true; break }
                _ = try await boundary.load()
                guard exact(record.registration, boundary.registration.server.registration),
                      known.contains(where: { exact($0, record.rendition.original) }),
                      try await allowsAuthority(record.rendition.original, requiresExisting: true) else { partial = true; continue }
                let result = await invalidations.invalidate(record)
                _ = try await boundary.load()
                guard case .succeeded(let ack) = result, exact(ack.record, record) else { partial = true; continue }
                do {
                    try await didInvalidate(ack)
                    _ = try await boundary.load()
                    unresolved.removeAll { exact($0, record) }
                } catch { partial = true }
            }

            var items: [StatusSynchronizationItem] = []
            for original in known {
                guard await admission() else {
                    partial = true
                    items.append(.init(original: original, disposition: .unresolved)); continue
                }
                _ = try await boundary.load()
                let disposition = try await synchronize(original)
                if disposition == .unresolved { partial = true }
                items.append(.init(original: original, disposition: disposition))
            }
            guard await admission() else {
                return .init(phase: .waitingForCapture, items: items, hasMore: after != nil,
                             unresolvedInvalidations: unresolved.count)
            }
            _ = try await boundary.load()
            let delivery = await outbox.synchronize()
            let latest = try await boundary.load()
            if case .succeeded = delivery {} else { partial = true }
            for index in items.indices {
                let original = items[index].original
                if unresolved.contains(where: { exact($0.rendition.original, original) })
                    || latest.outbox.contains(where: { exact(Self.original($0), original) }) {
                    items[index] = .init(original: original, disposition: .unresolved)
                    partial = true
                }
            }
            return .init(phase: partial || recoveredAuthorityWithoutManifest || after != nil || !unresolved.isEmpty ? .partial : .checked,
                         items: items, hasMore: after != nil, unresolvedInvalidations: unresolved.count)
        } catch {
            return .init(phase: .unavailable, hasMore: after != nil, unresolvedInvalidations: unresolved.count)
        }
    }

    private func synchronize(_ original: OriginalContent) async throws -> StatusSynchronizationDisposition {
        let snapshot = try await boundary.load()
        if let mutation = pending.first(where: { exact(Self.original($0), original) }) {
            // Reconcile the original complete command before fetching a newer
            // response. Unknown commit never permits rebasing or a new command.
            let result = await PublicationStoreBoundary.reconcile(mutation, store: store)
            let latest = try await boundary.load()
            guard committed(result, mutation: mutation), contains(mutation, in: latest) else { return .unresolved }
            pending.removeAll { exact($0, mutation) }
            if case .publication = mutation.change {
                // Only the authority command is reconciled here. A later
                // explicit poll must also persist current manifest metadata;
                // do not report the whole poll checked before that happens.
                recoveredAuthorityWithoutManifest = true
            }
            return .recorded
        }
        let result = await remote.manifest(original: original, registration: boundary.registration.server.registration)
        let latest = try await boundary.load()
        guard case .succeeded(let manifest) = result else { return .unresolved }
        do {
            try PublicationManifestValidation.validate(manifest, original: original)
            if let previous = latest.publicationManifests.last(where: {
                exact($0.observation.registration, boundary.registration.server.registration)
                    && exact($0.observation.original, original)
            }) { try PublicationManifestValidation.successor(manifest, to: previous.observation.manifest) }
            if let prior = latest.publications.last(where: {
                exact($0.observation.registration, boundary.registration.server.registration)
                    && exact($0.observation.rendition.original, original)
            }) {
                guard manifest.revision >= prior.observation.observation.rawValue else { return .unresolved }
                if manifest.revision == prior.observation.observation.rawValue,
                   !exact(manifest.current, prior.observation.rendition) { return .unresolved }
            }
        } catch { return .unresolved }
        let disposition = try await adopt(manifest, original: original, snapshot: snapshot, latest: latest)
        // Preserve an unknown authority mutation before adding any independent
        // metadata command. A rejected adoption still permits a truthful
        // metadata observation, but never changes the authority or its result.
        if pending.contains(where: { exact(Self.original($0), original) }) { return .unresolved }
        guard await admission() else { return .unresolved }
        let current = try await boundary.load()
        if let previous = current.publicationManifests.last(where: {
            exact($0.observation.registration, boundary.registration.server.registration)
                && exact($0.observation.original, original)
        }), exact(previous.observation.manifest, manifest) { return disposition }
        let observation = PublicationManifestObservation(command: .init(rawValue: UUID().uuidString),
            storeIdentity: boundary.identity, registration: boundary.registration.server.registration,
            original: original, manifest: manifest)
        let mutation = BackendStoreMutation(expectedRevision: current.revision,
            change: .publicationManifest(observation), expectedStoreIdentity: boundary.identity)
        pending.append(mutation)
        let resultCommit = await PublicationStoreBoundary.commit(mutation, store: store)
        let confirmed = try await boundary.load()
        guard committed(resultCommit, mutation: mutation), contains(mutation, in: confirmed) else {
            if case .rejected = resultCommit { pending.removeAll { exact($0, mutation) } }
            return .unresolved
        }
        pending.removeAll { exact($0, mutation) }
        return disposition
    }

    private func contains(_ mutation: BackendStoreMutation, in snapshot: BackendStoreSnapshot) -> Bool {
        switch mutation.change {
        case .publication(let value): snapshot.publications.contains { exact($0.observation, value) }
        case .publicationManifest(let value): snapshot.publicationManifests.contains { $0.isCommitted && exact($0.observation, value) }
        default: false
        }
    }

    private static func original(_ mutation: BackendStoreMutation) -> OriginalContent? {
        switch mutation.change {
        case .publication(let value): value.rendition.original
        case .publicationManifest(let value): value.original
        default: nil
        }
    }

    private func adopt(_ manifest: PublicationManifest, original: OriginalContent,
        snapshot: BackendStoreSnapshot, latest: BackendStoreSnapshot) async throws -> StatusSynchronizationDisposition {
        let prior = latest.publications.last(where: {
            exact($0.observation.registration, boundary.registration.server.registration)
                && exact($0.observation.rendition.original, original)
        })
        guard let rendition = manifest.current else {
            // A nil manifest has its own metadata command. It cannot clear
            // publication/confirmation authority or become an invalidation.
            return prior == nil ? .noPublishedRecord : .unresolved
        }
        guard exact(rendition.original, original), manifest.mediaType != nil,
              try await allowsAuthority(original, at: latest.revision) else { return .unresolved }
        if let prior {
            guard manifest.revision >= prior.observation.observation.rawValue else { return .unresolved }
            if exact(prior.observation.rendition, rendition) {
                guard let state = latest.confirmationStates.first(where: {
                    exact($0.registration, boundary.registration.server.registration) && exact($0.current.original, original)
                }), exact(state.current, rendition), state.generation == manifest.invalidationGeneration else { return .unresolved }
                if prior.observation.invalidationGeneration == manifest.invalidationGeneration { return .unchanged }
                // V1 may remain the server pointer while replacement waits for
                // other registrations. Its pointer revision need not advance.
                // Reconcile the exact local tombstone instead of manufacturing
                // a second publication or restoring the invalidated confirmation.
                if let ack = state.invalidation, ack.isCommitted,
                   exact(ack.record.rendition, rendition), exact(ack.record.registration, boundary.registration.server.registration),
                   ack.record.generation == manifest.invalidationGeneration,
                   state.invalidatedRenditions.contains(rendition.rendition),
                   latest.invalidations.contains(where: { exact($0, ack) }) {
                    let result = await store.lookupInvalidation(ack)
                    _ = try await boundary.load()
                    if case .succeeded(let id) = result, exact(id, ack.record.id) { return .unchanged }
                    return .unresolved
                }
            }
        }
        // Same mapping as PublicationHTTPBinding.open. Do not allocate a local
        // generation or bypass the writer's receipt/ACK/publication guards.
        guard manifest.revision > (prior?.observation.observation.rawValue ?? 0) else { return .unresolved }
        guard await admission() else { return .unresolved }
        let current = try await boundary.load()
        guard current.revision >= snapshot.revision,
              try await allowsAuthority(original, at: current.revision) else { return .unresolved }
        let observation = PublishedRenditionObservation(command: .init(rawValue: UUID().uuidString),
            registration: boundary.registration.server.registration, rendition: rendition,
            observation: .init(rawValue: manifest.revision), invalidationGeneration: manifest.invalidationGeneration)
        let mutation = BackendStoreMutation(expectedRevision: current.revision, change: .publication(observation),
                                            expectedStoreIdentity: boundary.identity)
        pending.append(mutation)
        let committedResult = await PublicationStoreBoundary.commit(mutation, store: store)
        let confirmed = try await boundary.load()
        guard committed(committedResult, mutation: mutation),
              confirmed.publications.contains(where: { exact($0.observation, observation) }) else {
            if case .rejected = committedResult { pending.removeAll { exact($0, mutation) } }
            return .unresolved
        }
        pending.removeAll { exact($0, mutation) }
        return .recorded
    }

    /// The legacy authority writer compares capture Strings canonically. New
    /// catalog metadata preserves UTF-8 identities, so never pass an alias to
    /// that writer or to ordering for an existing, byte-distinct original.
    private func allowsAuthority(_ original: OriginalContent, at revision: UInt64? = nil,
        requiresExisting: Bool = false) async throws -> Bool {
        guard case .succeeded(let originals) = await store.loadOriginalState() else {
            throw BackendContractError.unavailable
        }
        let backend = try await boundary.load()
        if let revision {
            guard originals.revision == revision, backend.revision == revision else { return false }
        }
        let matches = originals.logicalOriginals.filter { $0.original.capture == original.capture }
        guard matches.allSatisfy({ exact($0.original, original) }) else { return false }
        // Logical original identity is immutable. An exact existing identity
        // cannot become a different alias while the invalidator is awaited.
        return !requiresExisting || matches.contains(where: { exact($0.original, original) })
    }

    private func retain(_ record: InvalidationRecord) {
        if !unresolved.contains(where: { exact($0, record) }) { unresolved.append(record) }
    }
    private func valid(_ page: PublicationInvalidationPage, after: InvalidationID?) -> Bool {
        guard page.records.count <= 8 else { return false }
        let ids = page.records.map { $0.id.rawValue }
        guard zip(ids, ids.dropFirst()).allSatisfy({ $0.utf8.lexicographicallyPrecedes($1.utf8) }),
              after == nil || ids.allSatisfy({ after!.rawValue.utf8.lexicographicallyPrecedes($0.utf8) }),
              page.records.allSatisfy({ exact($0.registration, boundary.registration.server.registration) }) else { return false }
        if let next = page.nextAfter { return page.records.last.map { exact($0.id, next) } ?? false }
        return true
    }
    private func committed(_ result: BackendCommitResult, mutation: BackendStoreMutation) -> Bool {
        guard case .committed(let receipt) = result else { return false }
        return receipt.matches(mutation.change.key, revision: mutation.expectedRevision) && exact(receipt.key, mutation.change.key)
    }
    private func exact<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool { PublicationStoreBoundary.exact(lhs, rhs) }
    private static func original(_ entry: BackendSyncEntry) -> OriginalContent {
        switch entry {
        case .confirmation(let value): value.intent.playback.distribution.rendition.original
        case .invalidation(let value): value.record.rendition.original
        }
    }
}

/// Snapshot checks are also used around the nested outbox/external awaits.
nonisolated struct StatusSynchronizationRegistrationBoundary: Sendable {
    let store: any MediaOperationStorePort
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    func load() async throws -> BackendStoreSnapshot {
        let value = try await PublicationStoreBoundary.load(store, identity: identity)
        guard registration.isCommitted,
              PublicationStoreBoundary.exact(registration.server.intent.destination, registration.server.registration.destination),
              PublicationStoreBoundary.exact(registration.intentCommit.key,
                BackendCommitKey.registrationIntent(registration.server.intent.operation, registration.server.intent.destination)),
              PublicationStoreBoundary.exact(registration.commit.key,
                BackendCommitKey.registration(registration.server.intent.operation, registration.server.registration)),
              let current = value.registrations.last(where: {
                  $0.server.registration.destination == registration.server.registration.destination
              }), PublicationStoreBoundary.exact(current, registration),
              value.registrationIntents.contains(where: {
                  PublicationStoreBoundary.exact($0.intent, registration.server.intent)
                    && PublicationStoreBoundary.exact($0.commit, registration.intentCommit)
              }) else { throw BackendContractError.identityMismatch }
        return value
    }
}

/// Deliberately refuses media distribution. Historical outbox entries keep
/// their original registration and credentials; they are never re-addressed.
actor StatusSynchronizationRemote: PublicationRemotePort {
    private let base: any PublicationRemotePort
    private let boundary: StatusSynchronizationRegistrationBoundary
    private let admission: @MainActor @Sendable () -> Bool
    init(base: any PublicationRemotePort, boundary: StatusSynchronizationRegistrationBoundary,
         admission: @escaping @MainActor @Sendable () -> Bool) {
        self.base = base; self.boundary = boundary; self.admission = admission
    }
    private func perform<T: Equatable & Sendable>(_ operation: () async -> BackendOutcome<T>) async -> BackendOutcome<T> {
        do {
            guard await admission(), !Task.isCancelled else { return .inProgress }
            _ = try await boundary.load()
            let result = await operation()
            _ = try await boundary.load()
            guard await admission(), !Task.isCancelled else { return .unknown }
            _ = try await boundary.load()
            return result
        } catch { return .unknown }
    }
    func manifest(original: OriginalContent, registration: RegistrationIdentity) async -> BackendOutcome<PublicationManifest> {
        guard PublicationStoreBoundary.exact(registration, boundary.registration.server.registration) else { return .unknown }
        return await perform { await base.manifest(original: original, registration: registration) }
    }
    func invalidations(registration: RegistrationIdentity, after: InvalidationID?) async -> BackendOutcome<PublicationInvalidationPage> {
        guard PublicationStoreBoundary.exact(registration, boundary.registration.server.registration) else { return .unknown }
        return await perform { await base.invalidations(registration: registration, after: after) }
    }
    func send(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> { await perform { await base.send(entry) } }
    func lookup(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> { await perform { await base.lookup(entry) } }
    func distribute(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { .failed(.rejected) }
    func lookupDistribution(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { .failed(.rejected) }
}
