import Foundation

/// Owns the durable operation, independently of a view or its caller task.
/// This boundary accepts already-complete local media; it never downloads or
/// manufactures a conversion/publication receipt and has no network gate.
actor PhotoSaveCoordinator {
    private let store: any MediaOperationStorePort
    nonisolated private let identity: RegistrationStoreIdentity
    private let temporaryMedia: any TemporaryMediaPort & TemporaryLocalMediaPort
    private let library: any PhotoLibraryPort
    private let captureStart: (any PhotoSaveCaptureStartPort)?
    nonisolated private let dispatchClaims: PhotoSaveDispatchClaims
    nonisolated private let claimOwner = UUID()
    private var liveClaims: [Data: PhotoSaveDispatchClaim] = [:]
    private var saveTasks: [Data: Task<BackendOutcome<PhotoRegistrationRecord>, Never>] = [:]
    private var ownedRegistrations: [Data: CommittedPhotoRegistrationIntent] = [:]
    private var readWitnesses: [Data: PhotoSaveLocalReadWitness] = [:]
    private let reconciler: PhotoRegistrationReconciler
    private var running: Set<PhotoRegistrationKey> = []
    private var tasks: [PhotoRegistrationKey: Task<BackendOutcome<PhotoRegistrationRecord>, Never>] = [:]
    /// Uncertain mutations retain their original revision, command and payload.
    private var pending: [MediaOperationID: BackendStoreMutation] = [:]

    init(store: any MediaOperationStorePort, identity: RegistrationStoreIdentity,
         temporaryMedia: any TemporaryMediaPort & TemporaryLocalMediaPort,
         library: any PhotoLibraryPort, captureStart: (any PhotoSaveCaptureStartPort)? = nil,
         dispatchClaims: PhotoSaveDispatchClaims = .shared) {
        self.store = store; self.identity = identity
        self.temporaryMedia = temporaryMedia; self.library = library
        self.captureStart = captureStart; self.dispatchClaims = dispatchClaims
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
        return await start(intent, receipt: receipt)
    }

    /// Reuses the exact prior handoff as input only. performSave owns the one
    /// fresh retry use after proving that the latest result was a non-addition.
    func retry(_ previous: PhotoRegistrationIntent, action: MediaOperationID) async -> BackendOutcome<PhotoRegistrationRecord> {
        do {
            let intent = try PhotoRegistrationIntent(operation: action, handoff: previous.handoff, retryOf: previous.operation)
            return await start(intent)
        } catch { return .failed(.rejected) }
    }

    /// Product capabilities reserve the identical input synchronously before
    /// their first await. This closes cancellation's handoff-to-coordinator gap;
    /// start() must subsequently join this same owner/input, never a new claim.
    nonisolated func reserveSave(_ receipt: TemporaryMediaReceipt, action: MediaOperationID) -> PhotoSaveDispatchClaim? {
        guard let intent = try? PhotoRegistrationIntent(operation: action,
            handoff: receipt.photoHandoff(expected: receipt.rendition)) else { return nil }
        return dispatchClaims.reserve(identity: identity, intent: intent, receipt: receipt, owner: claimOwner)
    }

    nonisolated func reserveRetry(_ previous: PhotoRegistrationIntent, action: MediaOperationID) -> PhotoSaveDispatchClaim? {
        guard let intent = try? PhotoRegistrationIntent(operation: action, handoff: previous.handoff, retryOf: previous.operation) else { return nil }
        return dispatchClaims.reserve(identity: identity, intent: intent, receipt: nil, owner: claimOwner)
    }

    private func start(_ intent: PhotoRegistrationIntent,
                       receipt: TemporaryMediaReceipt? = nil) async -> BackendOutcome<PhotoRegistrationRecord> {
        guard !running.contains(intent.key) else { return .inProgress }
        // Shared exclusion is reserved before the first await, including source
        // preparation/intent commits. A second owner writes no result/terminal
        // and cannot retire the first owner's live use, even after its FD closes.
        guard let claim = dispatchClaims.reserve(identity: identity, intent: intent, receipt: receipt, owner: claimOwner) else { return .unknown }
        running.insert(intent.key)
        liveClaims[Data(intent.operation.rawValue.utf8)] = claim
        // Unstructured and retained by the application owner: cancellation of
        // the waiting UI task is not cancellation of an external side effect.
        let task = Task { await self.performSave(intent, claim: claim) }
        tasks[intent.key] = task
        saveTasks[Data(intent.operation.rawValue.utf8)] = task
        return await task.value
    }

    /// Explicit live predispatch cancellation. This does not cancel PhotoKit;
    /// a dispatched claim refuses and waits for its actual completion instead.
    @discardableResult func cancelBeforeStart(action: MediaOperationID) -> Bool {
        liveClaims[Data(action.rawValue.utf8)]?.cancelBeforeStart() ?? false
    }

    /// The shared capture hold is already closed by the REC owner. Cancel
    /// pending starts before joining; waiting for an uncancelled held task would
    /// deadlock against that very hold. Accepted SDK work has no cancel handle.
    func waitForCaptureLocalStop() async -> Bool {
        for _ in 0..<3 {
            guard let generation = dispatchClaims.generation(for: identity) else { return false }
            let retained = Array(saveTasks.values)
            for claim in liveClaims.values { _ = claim.cancelBeforeStart() }
            for task in retained { _ = await task.value }
            await recoverKnownNonStartedIntents()
            guard saveTasks.isEmpty else { continue }
            guard dispatchClaims.generation(for: identity) == generation else { continue }
            guard let snapshot = try? await load() else { return false }
            var recovered = false
            for (operation, registration) in ownedRegistrations {
                guard let record = snapshot.photoRegistrations.first(where: {
                    PhotoSaveBatchValueValidation.exact($0.registration.intent.operation, registration.intent.operation)
                }), PhotoSaveStartStoreBoundary.same(record.registration, registration),
                      readWitnesses[operation]?.isCurrent != true else { return false }
                if record.usageTerminal != nil, record.terminalUsageRelease == nil,
                   let recovery = temporaryMedia as? any PhotoTemporaryUsageRecoveryPort {
                    guard await recovery.recoverTerminalPhotoUsage(record) == .succeeded(registration.intent.media) else { return false }
                    recovered = true
                    continue
                }
                guard let proof = PhotoSaveStartStoreBoundary.localStopProof(record, identity: identity) else { return false }
                for (mutation, expected) in proof {
                    guard await lookup(mutation) == expected else { return false }
                }
            }
            if recovered { continue }
            // A live unknown intent response retains its use; absence of a
            // callback/dictionary entry cannot become a local-stop observation.
            guard !pending.values.contains(where: {
                if case .photo(_, .intent) = $0.change { return true }; return false
            }), let latest = try? await load(), latest.revision == snapshot.revision,
                saveTasks.isEmpty, dispatchClaims.generation(for: identity) == generation else { continue }
            return true
        }
        return false
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

    private func finishTask(_ key: PhotoRegistrationKey, operation: MediaOperationID? = nil) {
        tasks.removeValue(forKey: key); running.remove(key)
        if let operation {
            let key = Data(operation.rawValue.utf8)
            saveTasks.removeValue(forKey: key)
            liveClaims.removeValue(forKey: key)?.finish()
        }
    }

    private func performSave(_ requested: PhotoRegistrationIntent,
                             claim: PhotoSaveDispatchClaim) async -> BackendOutcome<PhotoRegistrationRecord> {
        var intent = requested
        var freshRetryUsage: TemporaryMediaUsage?
        defer { finishTask(intent.key, operation: intent.operation) }
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

            guard claim.bind(intent) else { return .unknown }
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
            ownedRegistrations[Data(intent.operation.rawValue.utf8)] = record.registration
            if claim.isCancelled {
                let terminal = try? await temporaryMedia.photoUsageTerminal(record.registration, termination: .notStarted)
                return await recordResult(intent, .notAttempted(.rejected), terminal: terminal)
            }
            let authorization = await authorize(.addOnly)
            if claim.isCancelled {
                let terminal = try? await temporaryMedia.photoUsageTerminal(record.registration, termination: .notStarted)
                return await recordResult(intent, .notAttempted(.rejected), terminal: terminal)
            }
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
            if let witness = local.photoReadWitness { readWitnesses[Data(intent.operation.rawValue.utf8)] = witness }
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
            let returned = await addWhenCapturePermits(add, claim: claim)
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

    private func addWhenCapturePermits(_ command: PhotoLibraryAddCommand,
                                      claim: PhotoSaveDispatchClaim) async -> PhotoRegistrationResult {
        let wakes = claim.wakes()
        // Subscribe before the first authorization probe. Both initial wake and
        // every capture change arrive without holding admission/claim locks.
        let changes = captureStart?.changes()
        let observer = changes.map { stream in Task {
            for await _ in stream { claim.wake() }
        } }
        defer { observer?.cancel() }
        for await _ in wakes {
            if claim.isCancelled { return .init(intent: command.registration.intent, outcome: .notAttempted(.rejected)) }
            let permit = captureStart?.authorizeResume()
            if captureStart != nil, permit == nil { continue }
            let attempt = await library.add(command, start: .init(store: store, capture: permit, claim: claim))
            switch attempt {
            case .heldBeforeStart: continue // Same intent/use/FD/live task; no second add intent.
            case .completed(let result): return result
            }
        }
        return .init(intent: command.registration.intent, outcome: .unknown(localIdentifier: nil))
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
