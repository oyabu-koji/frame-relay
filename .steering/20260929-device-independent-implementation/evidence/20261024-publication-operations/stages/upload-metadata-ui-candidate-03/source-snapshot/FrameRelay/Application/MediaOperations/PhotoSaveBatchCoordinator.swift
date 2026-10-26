import Foundation

/// App-lifetime queue of fixed local Photos targets. Neither a restored queue
/// nor a durable starting record is authority to replay a Photos SDK call.
actor PhotoSaveBatchCoordinator {
    private let store: any MediaOperationStorePort
    private let execution: any PhotoSaveBatchExecutionPort
    private let network: any PhotoSaveStartNetworkPort
    private let capture: CaptureMediaAdmission
    private let didChange: @Sendable () async -> Void
    private var pending: [MediaOperationID: BackendStoreMutation] = [:]
    private var requests: [MediaOperationID: PhotoSaveBatchRequest] = [:]
    private var proposed: [MediaOperationID: PhotoSaveBatch] = [:]
    private var prepared: [MediaOperationID: any PreparedPhotoSavePort] = [:]
    private var active: Set<MediaOperationID> = []
    private var cancelled: Set<MediaOperationID> = []
    private var drivers: [MediaOperationID: Task<Void, Never>] = [:]
    private var wakeRequested: Set<MediaOperationID> = []
    private var resolving: Set<MediaOperationID> = []

    init(store: any MediaOperationStorePort, execution: any PhotoSaveBatchExecutionPort,
         network: any PhotoSaveStartNetworkPort, capture: CaptureMediaAdmission,
         didChange: @escaping @Sendable () async -> Void = {}) {
        self.store = store; self.execution = execution; self.network = network
        self.capture = capture; self.didChange = didChange
    }

    /// The path gate precedes every new accept, preparation, use and SDK call.
    /// Once accepted, this completely local job does not need continuing Wi-Fi.
    func submit(_ request: PhotoSaveBatchRequest) async -> LibraryCommandResponse {
        if let old = requests[request.operation] {
            guard sameRequest(old, request), let batch = proposed[request.operation] else { return .rejected("受付対象が一致しません。") }
            return await accept(batch)
        }
        guard network.currentCondition() == .wiFi else { return .rejected(Self.wifiReason) }
        guard resolving.insert(request.operation).inserted else { return .unknown }
        defer { resolving.remove(request.operation) }
        guard !request.targets.isEmpty else { return .rejected("写真に保存する動画を選択してください。") }
        do {
            let snapshot = try await load()
            guard snapshot.revision == request.displayedRevision else {
                return .rejected("保存記録が更新されました。表示を再読み込みして対象を確認してください。")
            }
            guard let identity = snapshot.storeIdentity else { return .rejected("現在の端末登録を確認してください。") }
            var targets: [PhotoSaveBatchTarget] = []
            for target in request.targets {
                let source = try await execution.source(for: target)
                guard source.storeIdentity == identity else { return .rejected("保存先の登録が更新されました。") }
                targets.append(try .init(source: source, operation: .init(rawValue: UUID().uuidString)))
            }
            let batch = try PhotoSaveBatch(operation: request.operation, storeIdentity: identity, targets: targets)
            let fixed = try await load()
            guard fixed.revision == request.displayedRevision, fixed.storeIdentity == identity else {
                return .rejected("対象を固定する間に保存記録が更新されました。再読み込みしてください。")
            }
            guard network.currentCondition() == .wiFi else { return .rejected(Self.wifiReason) }
            requests[request.operation] = request; proposed[request.operation] = batch
            return await accept(batch)
        } catch { return .rejected("現在の完全取得済み軽量版を固定できません。記録を再読み込みしてください。") }
    }

    func retry(source: PhotoSaveSource, previous: MediaOperationID, operation: MediaOperationID) async -> LibraryCommandResponse {
        if let retained = proposed[operation] {
            guard PhotoSaveBatchValueValidation.exact(retained.operation, operation), retained.targets.count == 1,
                  PhotoSaveBatchValueValidation.exact(retained.targets[0].source, source),
                  PhotoSaveBatchValueValidation.exact(retained.targets[0].retryOf, Optional(previous)) else {
                return .rejected("再試行の固定対象が一致しません。")
            }
            return await accept(retained)
        }
        guard network.currentCondition() == .wiFi else { return .rejected(Self.wifiReason) }
        guard resolving.insert(operation).inserted else { return .unknown }
        defer { resolving.remove(operation) }
        do {
            let current = try await execution.source(for: .init(original: source.rendition.original,
                destination: source.registration.destination))
            guard PhotoSaveBatchValueValidation.exact(current, source) else { return .rejected("軽量版の対象が更新されました。") }
            let target = try PhotoSaveBatchTarget(source: source, operation: .init(rawValue: UUID().uuidString), retryOf: previous)
            let batch = try PhotoSaveBatch(operation: operation, storeIdentity: source.storeIdentity, targets: [target])
            guard network.currentCondition() == .wiFi else { return .rejected(Self.wifiReason) }
            proposed[operation] = batch
            return await accept(batch)
        } catch { return .rejected("この登録結果からは再試行できません。記録を再読み込みしてください。") }
    }

    /// Explicit user actions, not restore or capture wake, admit old queues.
    func resume(_ operation: MediaOperationID) async {
        guard let snapshot = try? await load(), let record = snapshot.photoSaveBatches.first(where: {
            PhotoSaveBatchValueValidation.exact($0.batch.operation, operation)
        }), record.isCommitted, record.batch.storeIdentity == snapshot.storeIdentity else { return }
        for child in record.targets where child.registration != nil {
            await execution.reconcileKnownNonStarted(child.target)
        }
        active.insert(operation)
        if drivers[operation] != nil { wakeRequested.insert(operation) }
        else { schedule(operation) }
    }

    func cancel(_ operation: MediaOperationID) async {
        let known = proposed[operation]?.operation ?? active.first(where: { $0 == operation })
        if let known {
            guard PhotoSaveBatchValueValidation.exact(known, operation) else { return }
        } else {
            // A restored job has no live SDK-start capability. Establish its
            // exact ID before admitting a cancellation of its queued children.
            guard let snapshot = try? await load(), snapshot.photoSaveBatches.contains(where: {
                PhotoSaveBatchValueValidation.exact($0.batch.operation, operation)
                    && $0.batch.storeIdentity == snapshot.storeIdentity
            }) else { return }
        }
        // Set before suspension. A lost begin response that resolves later must
        // never cause the first SDK invocation after this cancellation.
        cancelled.insert(operation); active.insert(operation)
        if drivers[operation] != nil { wakeRequested.insert(operation) }
        else { schedule(operation) }
    }

    func captureDidChange() {
        guard !capture.snapshot().isHeld else { return }
        for operation in active {
            if drivers[operation] != nil { wakeRequested.insert(operation) }
            else { schedule(operation) }
        }
    }

    func waitForIdle() async {
        while let task = drivers.values.first { await task.value }
    }

    private func accept(_ batch: PhotoSaveBatch) async -> LibraryCommandResponse {
        if pending[batch.operation] == nil {
            guard let snapshot = try? await load(), snapshot.storeIdentity == batch.storeIdentity else { return .unknown }
            if let record = snapshot.photoSaveBatches.first(where: { $0.batch.operation == batch.operation }) {
                guard record.isCommitted, PhotoSaveBatchValueValidation.exact(record.batch, batch),
                      await lookup(record.mutation) == record.commit else { return .rejected("受付対象が一致しません。") }
                active.insert(batch.operation); schedule(batch.operation)
                return .accepted
            }
            // A retained proposal without an uncertain mutation is still a
            // new acceptance, so its current path must pass the initial gate.
            guard network.currentCondition() == .wiFi else { return .rejected(Self.wifiReason) }
        }
        let result = await persist(.accept(batch), command: batch.operation, identity: batch.storeIdentity)
        guard case .committed = result else {
            if case .rejected = result {
                requests.removeValue(forKey: batch.operation); proposed.removeValue(forKey: batch.operation)
                return .rejected("写真保存要求を受け付けられません。記録を確認してください。")
            }
            return .unknown
        }
        active.insert(batch.operation); schedule(batch.operation)
        await didChange()
        return .accepted
    }

    private func schedule(_ operation: MediaOperationID) {
        guard drivers[operation] == nil else { return }
        drivers[operation] = Task { await self.drive(operation) }
    }

    private func drive(_ operation: MediaOperationID) async {
        defer {
            drivers.removeValue(forKey: operation)
            if wakeRequested.remove(operation) != nil, active.contains(operation), !capture.snapshot().isHeld { schedule(operation) }
        }
        guard active.contains(operation), let initial = try? await load(),
              let batch = initial.photoSaveBatches.first(where: { PhotoSaveBatchValueValidation.exact($0.batch.operation, operation) }),
              batch.isCommitted, batch.batch.storeIdentity == initial.storeIdentity else { return }
        for target in batch.batch.targets {
            guard let snapshot = try? await load(), snapshot.storeIdentity == batch.batch.storeIdentity,
                  let child = snapshot.photoSaveBatches.first(where: { PhotoSaveBatchValueValidation.exact($0.batch, batch.batch) })?
                    .targets.first(where: { PhotoSaveBatchValueValidation.exact($0.target, target) }) else { return }
            if child.registration != nil { continue }
            switch child.status {
            case .notProcessed: continue
            case .starting(let begun):
                // A reopened starting record has no live capability and cannot
                // start Photos. Only a capability retained by this instance can.
                guard let capability = prepared[target.operation] else { continue }
                if let retained = pending[target.operation], !PhotoSaveBatchValueValidation.exact(retained, begun.mutation) { continue }
                guard await lookup(begun.mutation) == begun.commit else { continue }
                pending.removeValue(forKey: target.operation)
                await performOrHold(capability, child: begun)
            case .queued:
                if pending[target.operation] != nil {
                    if let mutation = pending[target.operation], case .photoBatch(_, .notProcessed(_, _, let reason)) = mutation.change {
                        await markUnprocessed(batch.batch, target: target, reason: reason); continue
                    }
                    // The original exact begin mutation is the only candidate;
                    // cancellation must not replace it with notProcessed.
                    let begun = await begin(batch.batch, target: target)
                    if let begun, let capability = prepared[target.operation] {
                        await performOrHold(capability, child: begun)
                    }
                    continue
                }
                if cancelled.contains(operation) {
                    await markUnprocessed(batch.batch, target: target, reason: .cancelled); continue
                }
                guard !capture.snapshot().isHeld else { continue }
                let capability: any PreparedPhotoSavePort
                do {
                    if let existing = prepared[target.operation] { capability = existing }
                    else {
                        capability = try await execution.prepare(target)
                        prepared[target.operation] = capability
                    }
                } catch {
                    await markUnprocessed(batch.batch, target: target, reason: .unavailable); continue
                }
                if cancelled.contains(operation) {
                    if await capability.releaseIfNotStarted() {
                        prepared.removeValue(forKey: target.operation)
                        await markUnprocessed(batch.batch, target: target, reason: .cancelled)
                    }
                    continue
                }
                // Keep the last use through a REC hold. A wake reads admission
                // again; it never trusts an old empty-owner notification.
                guard !capture.snapshot().isHeld else { continue }
                if let begun = await begin(batch.batch, target: target) {
                    await performOrHold(capability, child: begun)
                } else if pending[target.operation] == nil {
                    if await capability.releaseIfNotStarted() { prepared.removeValue(forKey: target.operation) }
                    await markUnprocessed(batch.batch, target: target, reason: .ineligible)
                }
            }
        }
        if let latest = try? await load(), let record = latest.photoSaveBatches.first(where: {
            PhotoSaveBatchValueValidation.exact($0.batch.operation, operation)
        }) {
            let waitsForCapture = !cancelled.contains(operation) && record.targets.contains { child in
                guard child.registration == nil, pending[child.target.operation] == nil else { return false }
                switch child.status {
                case .queued: return true
                case .starting: return prepared[child.target.operation] != nil
                case .notProcessed: return false
                }
            }
            // Completed history and uncertain non-live starts stay durable but
            // leave the automatic wake set. Only an explicit action readmits them.
            if !waitsForCapture { active.remove(operation) }
        }
        await didChange()
    }

    private func performOrHold(_ capability: any PreparedPhotoSavePort, child: CommittedPhotoSaveBatchChild) async {
        if cancelled.contains(child.batch) {
            // SDK non-start is known only for this retained capability. The
            // durable starting reservation remains uncertain, never cancelled
            // or queued: notProcessed is legal only before begin commits.
            if await capability.releaseIfNotStarted() { prepared.removeValue(forKey: child.target.operation) }
            return
        }
        guard !capture.snapshot().isHeld else { return }
        let result = await capability.perform(child)
        if result == .inProgress { return }
        // No outer release after perform, including unknown. Its owner alone
        // knows whether PhotoKit and its file lifetime actually terminated.
        prepared.removeValue(forKey: child.target.operation)
        await didChange()
    }

    private func begin(_ batch: PhotoSaveBatch, target: PhotoSaveBatchTarget) async -> CommittedPhotoSaveBatchChild? {
        guard case .committed(let receipt) = await persist(.beginChild(batch: batch.operation, target: target),
            command: target.operation, identity: batch.storeIdentity),
              let snapshot = try? await load(), let child = snapshot.photoSaveBatches.first(where: {
                  PhotoSaveBatchValueValidation.exact($0.batch, batch)
              })?.targets.first(where: { PhotoSaveBatchValueValidation.exact($0.target, target) }),
              case .starting(let begun) = child.status, begun.commit == receipt, begun.isCommitted else { return nil }
        return begun
    }

    private func markUnprocessed(_ batch: PhotoSaveBatch, target: PhotoSaveBatchTarget, reason: PhotoSaveBatchNonProcessing) async {
        _ = await persist(.notProcessed(batch: batch.operation, target: target, reason: reason),
            command: target.operation, identity: batch.storeIdentity)
    }

    private func load() async throws -> BackendStoreSnapshot {
        guard case .loaded(let snapshot) = await store.load() else { throw BackendContractError.unavailable }
        return snapshot
    }

    private func lookup(_ mutation: BackendStoreMutation) async -> BackendCommitReceipt? {
        guard case .committed(let receipt) = await store.lookupCommit(mutation),
              receipt.matches(mutation.change.key, revision: mutation.expectedRevision),
              PhotoSaveBatchValueValidation.exact(receipt.key, mutation.change.key) else { return nil }
        return receipt
    }

    private func persist(_ change: PhotoSaveBatchChange, command: MediaOperationID,
                         identity: RegistrationStoreIdentity) async -> BackendCommitResult {
        let value = BackendStoreChange.photoBatch(command: command, value: change)
        if let retained = pending[command] {
            guard PhotoSaveBatchValueValidation.exact(retained.change, value), retained.expectedStoreIdentity == identity else {
                return .rejected(.identityMismatch)
            }
            guard let receipt = await lookup(retained) else { return .unknown }
            pending.removeValue(forKey: command); return .committed(receipt)
        }
        for _ in 0..<3 {
            guard let snapshot = try? await load(), snapshot.storeIdentity == identity else { return .unknown }
            if case .accept = change, network.currentCondition() != .wiFi { return .rejected(.notOnWiFi) }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: value, expectedStoreIdentity: identity)
            pending[command] = mutation
            let result = await store.commit(mutation)
            if case .rejected(.revisionConflict) = result { pending.removeValue(forKey: command); continue }
            if case .rejected = result { pending.removeValue(forKey: command); return result }
            guard let receipt = await lookup(mutation) else { return .unknown }
            pending.removeValue(forKey: command); return .committed(receipt)
        }
        return .rejected(.revisionConflict)
    }

    private func sameRequest(_ lhs: PhotoSaveBatchRequest, _ rhs: PhotoSaveBatchRequest) -> Bool {
        guard PhotoSaveBatchValueValidation.exact(lhs.operation, rhs.operation),
              lhs.displayedRevision == rhs.displayedRevision, lhs.targets.count == rhs.targets.count else { return false }
        return zip(lhs.targets, rhs.targets).allSatisfy {
            PhotoSaveBatchValueValidation.exact($0.original, $1.original)
                && PhotoSaveBatchValueValidation.exact($0.destination, $1.destination)
        }
    }

    nonisolated static let wifiReason = "写真への新しい保存要求は、現在のWi-Fi経路を確認できるときに受け付けます。初期状態・オフライン・モバイル回線・経路不明では開始しません。"
}
