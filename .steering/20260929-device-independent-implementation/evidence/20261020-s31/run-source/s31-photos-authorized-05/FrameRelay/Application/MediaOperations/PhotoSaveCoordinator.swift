import Foundation

/// Owns the durable operation, independently of a view or its caller task.
/// This boundary accepts already-complete local media; it never downloads or
/// manufactures a conversion/publication receipt and has no network gate.
actor PhotoSaveCoordinator {
    private let store: any MediaOperationStorePort
    private let identity: RegistrationStoreIdentity
    private let temporaryMedia: any TemporaryMediaPort & TemporaryLocalMediaPort
    private let library: any PhotoLibraryPort
    private let reconciler: PhotoRegistrationReconciler
    private var running: Set<PhotoRegistrationKey> = []
    private var tasks: [PhotoRegistrationKey: Task<BackendOutcome<PhotoRegistrationRecord>, Never>] = [:]
    /// Uncertain mutations retain their original revision, command and payload.
    private var pending: [MediaOperationID: BackendStoreMutation] = [:]

    init(store: any MediaOperationStorePort, identity: RegistrationStoreIdentity,
         temporaryMedia: any TemporaryMediaPort & TemporaryLocalMediaPort,
         library: any PhotoLibraryPort) {
        self.store = store; self.identity = identity
        self.temporaryMedia = temporaryMedia; self.library = library
        reconciler = .init(store: store, identity: identity, library: library)
    }

    /// Only an explicit save action calls this method. An existing intent alone
    /// is ambiguous after restart and never authorizes another PhotoKit add.
    func save(_ receipt: TemporaryMediaReceipt, action: MediaOperationID,
              retryOf: MediaOperationID? = nil) async -> BackendOutcome<PhotoRegistrationRecord> {
        let intent: PhotoRegistrationIntent
        do {
            intent = try .init(operation: action, handoff: receipt.photoHandoff(expected: receipt.rendition), retryOf: retryOf)
        } catch { return .failed(.rejected) }
        guard running.insert(intent.key).inserted else { return .inProgress }
        // Unstructured and retained by the application owner: cancellation of
        // the waiting UI task is not cancellation of an external side effect.
        let task = Task { await self.performSave(intent) }
        tasks[intent.key] = task
        return await task.value
    }

    /// An explicit result-check action is the only readWrite request producer.
    /// Without an identifier, authorization cannot establish correspondence.
    func reconcile(_ key: PhotoRegistrationKey, action: MediaOperationID) async -> BackendOutcome<PhotoRegistrationRecord> {
        guard running.insert(key).inserted else { return .inProgress }
        let task = Task { await self.performReconciliation(key, action: action) }
        tasks[key] = task
        return await task.value
    }

    /// Restoring never requests authorization, searches Photos or adds media.
    func restore() async -> BackendOutcome<[PhotoRegistrationRecord]> {
        do {
            let records = try await load().photoRegistrations
            if let recovery = temporaryMedia as? any PhotoTemporaryUsageRecoveryPort {
                for record in records where !running.contains(record.registration.intent.key) {
                    guard case .succeeded? = record.outcome else { continue }
                    let result = await recovery.recoverSuccessfulPhotoUsage(record)
                    if result == .notExecuted { continue }
                    guard result == .succeeded(record.registration.intent.media) else { return .unknown }
                }
            }
            return .succeeded(try await load().photoRegistrations)
        }
        catch { return .unknown }
    }

    private func finishTask(_ key: PhotoRegistrationKey) {
        tasks.removeValue(forKey: key); running.remove(key)
    }

    private func performSave(_ intent: PhotoRegistrationIntent) async -> BackendOutcome<PhotoRegistrationRecord> {
        defer { finishTask(intent.key) }
        do {
            let snapshot = try await load()
            if let same = snapshot.photoRegistrations.first(where: { $0.registration.intent.operation == intent.operation }) {
                guard same.registration.intent == intent else { return .failed(.rejected) }
                return same.outcome == nil ? .unknown : .succeeded(same)
            }
            guard !pending.values.contains(where: { $0.change.key.photoKey == intent.key }) else { return .unknown }
            if let previous = snapshot.photoRegistrations.last(where: { $0.registration.intent.key == intent.key }) {
                guard previous.outcome?.permitsExplicitRetry == true,
                      intent.retryOf == previous.registration.intent.operation,
                      intent.rendition == previous.registration.intent.rendition,
                      intent.capturedAt == previous.registration.intent.capturedAt else { return .failed(.rejected) }
            } else if intent.retryOf != nil { return .failed(.rejected) }

            let committed = await persist(.intent(intent), command: intent.operation)
            guard case .committed(let receipt) = committed else { return outcome(committed) }
            let current = try await load()
            guard let record = current.photoRegistrations.first(where: { $0.registration.intent == intent }),
                  record.registration.commit == receipt,
                  record.registration.isCommitted else { return .unknown }
            let authorization = await authorize(.addOnly)
            guard authorization == .authorized else {
                return await recordResult(intent, .notAttempted(authorization == .restricted ? .restricted : .authorizationRequired))
            }

            let local: TemporaryLocalMedia
            do { local = try await temporaryMedia.resolvePhotoMedia(intent.usage) }
            catch { return await recordResult(intent, .notAttempted(.invalidMedia)) }
            let add: PhotoLibraryAddCommand
            do { add = try .init(registration: record.registration, media: local) }
            catch {
                let closed = await closePhoto(intent.usage)
                return await recordResult(intent, closed ? .notAttempted(.invalidMedia) : .unknown(localIdentifier: nil))
            }
            // Recheck the exact historical mutation immediately before the SDK
            // call; a lost/mismatched writer response is never an add permit.
            guard await confirms(record.registration.mutation) else {
                _ = await closePhoto(intent.usage)
                return .unknown
            }
            let returned = await library.add(add)
            let closed = await closePhoto(intent.usage)
            let result: PhotoRegistrationOutcome
            if returned.intent != intent { result = .unknown(localIdentifier: nil) }
            else if !closed { result = .unknown(localIdentifier: returned.outcome.localIdentifier) }
            else { result = returned.outcome }
            return await recordResult(intent, result, mayRelease: closed)
        } catch { return .unknown }
    }

    private func performReconciliation(_ key: PhotoRegistrationKey, action: MediaOperationID) async -> BackendOutcome<PhotoRegistrationRecord> {
        defer { finishTask(key) }
        // Look up retained uncertain payloads; do not submit them with a new
        // revision or infer that an absent response meant no SDK work.
        for (command, mutation) in pending where mutation.change.key.photoKey == key {
            guard await confirms(mutation) else { return .unknown }
            pending.removeValue(forKey: command)
        }
        return await reconciler.reconcile(key, action: action)
    }

    private func authorize(_ access: PhotoLibraryAccess) async -> PhotoLibraryAuthorization {
        let status = await library.authorizationStatus(for: access)
        return status == .notDetermined ? await library.requestAuthorization(for: access) : status
    }

    private func closePhoto(_ usage: TemporaryMediaUsage) async -> Bool {
        do { try await temporaryMedia.finishPhotoMedia(usage); return true }
        catch { return false }
    }

    private func recordResult(_ intent: PhotoRegistrationIntent, _ outcome: PhotoRegistrationOutcome,
                              mayRelease: Bool = false) async -> BackendOutcome<PhotoRegistrationRecord> {
        let result = PhotoRegistrationResult(intent: intent, outcome: outcome)
        let command = MediaOperationID(rawValue: UUID().uuidString)
        let committed = await persist(.result(result), command: command)
        guard case .committed(let receipt) = committed else { return .unknown }
        do {
            let latest = try await load()
            guard let record = latest.photoRegistrations.first(where: { $0.registration.intent == intent }),
                  record.results.contains(where: { $0.command == command && $0.result == result && $0.commit == receipt }) else { return .unknown }
            if mayRelease, case .succeeded = outcome {
                guard await temporaryMedia.releaseUsage(intent.usage) == .succeeded(intent.media) else { return .unknown }
            }
            return .succeeded(record)
        } catch { return .unknown }
    }

    private func load() async throws -> BackendStoreSnapshot {
        guard case .loaded(let value) = await store.load(), value.storeIdentity == identity else {
            throw BackendContractError.unavailable
        }
        return value
    }

    private func confirms(_ mutation: BackendStoreMutation) async -> Bool {
        await lookup(mutation) != nil
    }

    private func lookup(_ mutation: BackendStoreMutation) async -> BackendCommitReceipt? {
        guard case .committed(let receipt) = await store.lookupCommit(mutation),
              receipt.matches(mutation.change.key, revision: mutation.expectedRevision) else { return nil }
        return receipt
    }

    private func persist(_ value: PhotoRegistrationChange, command: MediaOperationID) async -> BackendCommitResult {
        let change = BackendStoreChange.photo(command: command, value: value)
        if let retained = pending[command] {
            guard retained.change == change else { return .rejected(.identityMismatch) }
            guard let receipt = await lookup(retained) else { return .unknown }
            pending.removeValue(forKey: command)
            return .committed(receipt)
        }
        for _ in 0..<3 {
            guard let snapshot = try? await load() else { return .unknown }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: change, expectedStoreIdentity: identity)
            pending[command] = mutation
            let result = await store.commit(mutation)
            if case .rejected(.revisionConflict) = result { pending.removeValue(forKey: command); continue }
            if case .rejected = result { pending.removeValue(forKey: command); return result }
            guard let receipt = await lookup(mutation) else { return .unknown }
            pending.removeValue(forKey: command)
            return .committed(receipt)
        }
        return .rejected(.revisionConflict)
    }

    private func outcome(_ result: BackendCommitResult) -> BackendOutcome<PhotoRegistrationRecord> {
        if case .rejected = result { return .failed(.rejected) }
        return .unknown
    }
}

private extension BackendCommitKey {
    nonisolated var photoKey: PhotoRegistrationKey? {
        guard case .photo(_, let value) = self else { return nil }
        return value
    }
}
