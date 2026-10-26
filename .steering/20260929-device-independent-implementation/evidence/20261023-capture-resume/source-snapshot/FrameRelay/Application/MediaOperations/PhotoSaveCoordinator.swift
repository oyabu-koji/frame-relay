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
            await recoverKnownNonStartedIntents()
            let records = try await load().photoRegistrations
            if let recovery = temporaryMedia as? any PhotoTemporaryUsageRecoveryPort {
                for record in records where !running.contains(record.registration.intent.key) {
                    let result: BackendOutcome<TemporaryMediaID>
                    if record.usageTerminal != nil { result = await recovery.recoverTerminalPhotoUsage(record) }
                    else if case .succeeded? = record.outcome { result = await recovery.recoverSuccessfulPhotoUsage(record) }
                    else { continue }
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

    private func performSave(_ requested: PhotoRegistrationIntent) async -> BackendOutcome<PhotoRegistrationRecord> {
        var intent = requested
        var freshRetryUsage: TemporaryMediaUsage?
        defer { finishTask(intent.key) }
        do {
            await recoverKnownNonStartedIntents(allowing: intent.key)
            let snapshot = try await load()
            if let same = snapshot.photoRegistrations.first(where: { $0.registration.intent.operation == intent.operation }) {
                let stored = same.registration.intent
                let retryInput = stored.retryOf != nil && stored.retryOf == intent.retryOf
                    && stored.rendition == intent.rendition && stored.media == intent.media
                    && stored.capturedAt == intent.capturedAt
                    && snapshot.photoRegistrations.contains(where: {
                        $0.registration.intent.operation == stored.retryOf
                            && $0.registration.intent.usage == intent.usage
                    })
                guard stored == intent || retryInput else { return .failed(.rejected) }
                return same.outcome == nil ? .unknown : .succeeded(same)
            }
            guard !pending.values.contains(where: { $0.change.key.photoKey == intent.key }) else { return .unknown }
            if let previous = snapshot.photoRegistrations.last(where: { $0.registration.intent.key == intent.key }) {
                guard previous.outcome?.permitsExplicitRetry == true,
                      intent.retryOf == previous.registration.intent.operation,
                      intent.rendition == previous.registration.intent.rendition,
                      intent.media == previous.registration.intent.media,
                      intent.capturedAt == previous.registration.intent.capturedAt else { return .failed(.rejected) }
                // A proven non-addition may have retired its photo reader while
                // retaining the copy. Each explicit retry owns a fresh use;
                // a delayed release for the earlier request cannot retire it.
                guard case .succeeded(let usage) = await temporaryMedia.acquireUsage(intent.media, purpose: .photoHandoff,
                    usageID: .init(rawValue: UUID().uuidString)) else { return .unknown }
                freshRetryUsage = usage
                intent = try .init(operation: requested.operation,
                    handoff: .init(media: requested.media, rendition: requested.rendition,
                        capturedAt: requested.capturedAt, usage: usage), retryOf: requested.retryOf)
            } else if intent.retryOf != nil { return .failed(.rejected) }

            let committed = await persist(.intent(intent), command: intent.operation)
            guard case .committed(let receipt) = committed else {
                if case .rejected = committed, let usage = freshRetryUsage {
                    // A definite rejection proves this newly acquired use was
                    // never registered or passed to the SDK. Unknown commits
                    // keep their exact mutation/use for later reconciliation.
                    guard await temporaryMedia.releaseUsage(usage) == .succeeded(usage.media) else { return .unknown }
                }
                return outcome(committed)
            }
            let current = try await load()
            guard let record = current.photoRegistrations.first(where: { $0.registration.intent == intent }),
                  record.registration.commit == receipt,
                  record.registration.isCommitted else { return .unknown }
            let authorization = await authorize(.addOnly)
            guard authorization == .authorized else {
                let terminal = try? await temporaryMedia.photoUsageTerminal(record.registration, termination: .notStarted)
                return await recordResult(intent, .notAttempted(authorization == .restricted ? .restricted : .authorizationRequired), terminal: terminal)
            }

            let local: TemporaryLocalMedia
            do { local = try await temporaryMedia.resolvePhotoMedia(intent.usage) }
            catch {
                let terminal = try? await temporaryMedia.photoUsageTerminal(record.registration, termination: .notStarted)
                return await recordResult(intent, .notAttempted(.invalidMedia), terminal: terminal)
            }
            let add: PhotoLibraryAddCommand
            do { add = try .init(registration: record.registration, media: local) }
            catch {
                let closed = await closePhoto(intent.usage)
                let terminal = closed ? try? await temporaryMedia.photoUsageTerminal(record.registration, termination: .notStarted) : nil
                return await recordResult(intent, closed ? .notAttempted(.invalidMedia) : .unknown(localIdentifier: nil), terminal: terminal)
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
            let terminal: PhotoUsageTerminal?
            if closed, returned.intent == intent {
                let termination: PhotoUsageTermination
                if case .notAttempted = returned.outcome { termination = .notStarted }
                else { termination = .sdkCompleted }
                terminal = try? await temporaryMedia.photoUsageTerminal(record.registration, termination: termination)
            } else { terminal = nil }
            return await recordResult(intent, result, terminal: terminal)
        } catch { return .unknown }
    }

    private func performReconciliation(_ key: PhotoRegistrationKey, action: MediaOperationID) async -> BackendOutcome<PhotoRegistrationRecord> {
        defer { finishTask(key) }
        await recoverKnownNonStartedIntents(allowing: key)
        // Look up retained uncertain payloads; do not submit them with a new
        // revision or infer that an absent response meant no SDK work.
        for (command, mutation) in pending where mutation.change.key.photoKey == key {
            // Non-start provenance lives with the retained intent until its
            // terminal is committed; a lookup alone must not discard it.
            if case .photo(_, .intent) = mutation.change { return .unknown }
            guard await confirms(mutation) else { return .unknown }
            pending.removeValue(forKey: command)
        }
        return await reconciler.reconcile(key, action: action)
    }

    /// Only this live coordinator knows that an uncertain intent commit made it
    /// return before any SDK call. An intent loaded after restart has no such
    /// provenance and must remain unknown. Never resubmit an uncertain mutation.
    private func recoverKnownNonStartedIntents(allowing key: PhotoRegistrationKey? = nil) async {
        let retained = pending
        for (command, mutation) in retained {
            guard case .photo(_, .intent(let intent)) = mutation.change,
                  !running.contains(intent.key) || intent.key == key,
                  let receipt = await lookup(mutation), let snapshot = try? await load(),
                  let record = snapshot.photoRegistrations.first(where: { $0.registration.intent == intent }),
                  record.registration.commit == receipt, record.registration.mutation == mutation,
                  record.results.isEmpty else { continue }
            if record.usageTerminal != nil {
                pending.removeValue(forKey: command)
                continue
            }
            guard let terminal = try? await temporaryMedia.photoUsageTerminal(record.registration, termination: .notStarted) else { continue }
            let terminalCommand = pending.first(where: {
                if case .photo(_, .terminal(let value)) = $0.value.change { return value == terminal }
                return false
            })?.key ?? .init(rawValue: UUID().uuidString)
            guard case .committed = await persist(.terminal(terminal), command: terminalCommand) else { continue }
            pending.removeValue(forKey: command)
            _ = await temporaryMedia.releaseUsage(intent.usage)
        }
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
                              terminal: PhotoUsageTerminal? = nil) async -> BackendOutcome<PhotoRegistrationRecord> {
        let result = PhotoRegistrationResult(intent: intent, outcome: outcome)
        let command = MediaOperationID(rawValue: UUID().uuidString)
        let committed = await persist(.result(result), command: command)
        // Persist the independently observed SDK/file terminal even when the
        // result response was lost or rejected. That can retire the reader;
        // registration uncertainty still retains the copy and forbids re-add.
        var terminalConfirmed = false
        if let terminal {
            let terminalCommand = MediaOperationID(rawValue: UUID().uuidString)
            if case .committed = await persist(.terminal(terminal), command: terminalCommand) {
                terminalConfirmed = true
            }
        }
        if terminalConfirmed {
            guard await temporaryMedia.releaseUsage(intent.usage) == .succeeded(intent.media) else { return .unknown }
        }
        if terminal != nil, !terminalConfirmed { return .unknown }
        guard case .committed(let receipt) = committed else { return .unknown }
        do {
            let latest = try await load()
            guard let record = latest.photoRegistrations.first(where: { $0.registration.intent == intent }),
                  record.results.contains(where: { $0.command == command && $0.result == result && $0.commit == receipt }) else { return .unknown }
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
