import Foundation

/// Accepts a fixed local request only. Stat observations are neither a new
/// content verification nor permission to acquire/copy/send the original.
actor OriginalUploadAcceptanceCoordinator: OriginalUploadAcceptancePort {
    private let store: any RecordingStorePort & OriginalStorePort & MediaOperationStorePort
    private let files: any RecordingOriginalFilePort
    private let network: any OriginalUploadStartNetworkPort
    private let didRecord: @Sendable () async -> Void
    private var pending: [MediaOperationID: BackendStoreMutation] = [:]
    private var processing: [MediaOperationID: OriginalUploadAcceptanceRequest] = [:]
    private var notified: Set<MediaOperationID> = []

    init(store: any RecordingStorePort & OriginalStorePort & MediaOperationStorePort,
         files: any RecordingOriginalFilePort, network: any OriginalUploadStartNetworkPort,
         didRecord: @escaping @Sendable () async -> Void = {}) {
        self.store = store; self.files = files; self.network = network; self.didRecord = didRecord
    }

    func accept(_ request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult {
        do { try request.validate() } catch let error as BackendContractError { return .rejected(error) }
        catch { return .rejected(.invalidValue) }
        if let active = processing[request.parent] {
            return OriginalUploadAcceptanceValueValidation.exact(active, request) ? .unknown : .rejected(.identityMismatch)
        }
        if let mutation = pending[request.parent] {
            guard matches(mutation, request: request) else { return .rejected(.identityMismatch) }
            return await lookupAcceptance(request)
        }
        // Initial unknown/cellular/offline does not reserve a writer command.
        guard network.currentCondition() == .wiFi else { return .rejected(.notOnWiFi) }
        processing[request.parent] = request
        defer { processing.removeValue(forKey: request.parent) }
        for _ in 0..<3 {
            let before: OriginalUploadAcceptanceSnapshot
            do { before = try await load(request) } catch BackendContractError.revisionConflict { continue }
            catch let error as BackendContractError { return .rejected(error) }
            catch { return .rejected(.unavailable) }
            if let existing = before.backend.originalUploadAcceptances.first(where: { $0.plan.request.parent == request.parent }) {
                guard OriginalUploadAcceptanceValueValidation.exact(existing.plan.request, request), existing.isCommitted else {
                    return .rejected(.identityMismatch)
                }
                pending[request.parent] = existing.mutation
                return await reconcile(existing.mutation, request: request)
            }
            guard let current = OriginalUploadAcceptanceBoundary.currentRegistration(before.backend),
                  OriginalUploadAcceptanceValueValidation.exact(current, request.registration) else {
                return .rejected(.identityMismatch)
            }
            var presences: [OriginalUploadFilePresence] = []
            for target in request.targets {
                let file = await files.observeFile(target.binding.reference)
                switch file {
                case .present(let bytes): presences.append(.present(byteCount: bytes))
                case .absent: presences.append(.missing)
                case .unavailable(.resourceUnavailable), .unavailable(.permissionDenied): presences.append(.inaccessible)
                case .unavailable: presences.append(.unknown)
                }
            }
            let after: OriginalUploadAcceptanceSnapshot
            do { after = try await load(request) } catch BackendContractError.revisionConflict { continue }
            catch let error as BackendContractError { return .rejected(error) }
            catch { return .rejected(.unavailable) }
            guard before.backend.revision == after.backend.revision else { continue }
            guard OriginalUploadAcceptanceBoundary.sameBoundary(before, after, request: request),
                  let registration = OriginalUploadAcceptanceBoundary.currentRegistration(after.backend),
                  OriginalUploadAcceptanceValueValidation.exact(registration, request.registration) else {
                return .rejected(.identityMismatch)
            }
            guard network.currentCondition() == .wiFi else { return .rejected(.notOnWiFi) }
            let plan: OriginalUploadAcceptancePlan
            do { plan = try .init(request: request, presences: presences) }
            catch { return .rejected(.invalidValue) }
            let mutation = BackendStoreMutation(expectedRevision: after.backend.revision,
                change: .originalUploadAcceptance(plan), expectedStoreIdentity: request.storeIdentity)
            // A lost response retains this exact envelope, including revision
            // and stat results. Lookup never restats or proposes another value.
            pending[request.parent] = mutation
            switch await store.commit(mutation) {
            case .rejected(.revisionConflict):
                pending.removeValue(forKey: request.parent)
                continue
            case .rejected(let error):
                pending.removeValue(forKey: request.parent)
                return .rejected(error)
            case .committed, .unknown, .unavailable:
                return await reconcile(mutation, request: request)
            }
        }
        // Every proposal was definitely rejected; there is no orphan unknown.
        return .rejected(.revisionConflict)
    }

    func lookupAcceptance(_ request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult {
        guard processing[request.parent] == nil else { return .unknown }
        do { try request.validate() } catch { return .rejected(.invalidValue) }
        processing[request.parent] = request
        defer { processing.removeValue(forKey: request.parent) }
        if let mutation = pending[request.parent] {
            guard matches(mutation, request: request) else { return .rejected(.identityMismatch) }
            return await reconcile(mutation, request: request)
        }
        guard case .loaded(let snapshot) = await store.load() else { return .unknown }
        guard snapshot.storeIdentity == request.storeIdentity else { return .rejected(.identityMismatch) }
        guard let record = snapshot.originalUploadAcceptances.first(where: { $0.plan.request.parent == request.parent }) else {
            return .unknown
        }
        guard record.isCommitted, OriginalUploadAcceptanceValueValidation.exact(record.plan.request, request) else {
            return .rejected(.identityMismatch)
        }
        // Reopened owners reconstruct from the immutable record, never from
        // mutable current requests that may now contain a person's pause.
        pending[request.parent] = record.mutation
        return await reconcile(record.mutation, request: request)
    }

    private func reconcile(_ mutation: BackendStoreMutation,
        request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult {
        guard case .committed(let receipt) = await store.lookupCommit(mutation),
              receipt.matches(mutation.change.key, revision: mutation.expectedRevision),
              OriginalUploadAcceptanceValueValidation.exact(receipt.key, mutation.change.key),
              case .loaded(let snapshot) = await store.load(), snapshot.storeIdentity == request.storeIdentity,
              let record = snapshot.originalUploadAcceptances.first(where: {
                  OriginalUploadAcceptanceValueValidation.exact($0.plan.request, request)
              }), record.isCommitted, record.commit == receipt,
              OriginalUploadAcceptanceValueValidation.exact(record.mutation, mutation) else { return .unknown }
        if notified.insert(request.parent).inserted { await didRecord() }
        // Capture-wait synchronization can suspend. Keep the original envelope
        // until the current writer still exposes this exact immutable receipt.
        guard case .committed(let finalReceipt) = await store.lookupCommit(mutation), finalReceipt == receipt,
              OriginalUploadAcceptanceValueValidation.exact(finalReceipt.key, receipt.key),
              case .loaded(let latest) = await store.load(), latest.storeIdentity == request.storeIdentity,
              let final = latest.originalUploadAcceptances.first(where: {
                  OriginalUploadAcceptanceValueValidation.exact($0.plan.request, request)
              }), final.isCommitted, final == record, final.commit == finalReceipt,
              OriginalUploadAcceptanceValueValidation.exact(final.mutation, mutation) else { return .unknown }
        pending.removeValue(forKey: request.parent)
        return .recorded(final)
    }

    private func matches(_ mutation: BackendStoreMutation, request: OriginalUploadAcceptanceRequest) -> Bool {
        guard case .originalUploadAcceptance(let plan) = mutation.change else { return false }
        return mutation.expectedStoreIdentity == request.storeIdentity
            && OriginalUploadAcceptanceValueValidation.exact(plan.request, request)
    }

    private func load(_ request: OriginalUploadAcceptanceRequest) async throws -> OriginalUploadAcceptanceSnapshot {
        guard case .loaded(let recordings) = await store.loadRecordings(),
              case .succeeded(let originals) = await store.loadOriginalState(),
              case .loaded(let backend) = await store.load() else { throw BackendContractError.unavailable }
        guard backend.storeIdentity == request.storeIdentity else { throw BackendContractError.identityMismatch }
        guard recordings.revision == originals.revision, originals.revision == backend.revision else {
            throw BackendContractError.revisionConflict
        }
        guard Set(recordings.recordings.map { $0.intent.context.capture }).count == recordings.recordings.count,
              Set(recordings.recordings.map { $0.intent.original }).count == recordings.recordings.count,
              Set(originals.originals.map { $0.binding.original.capture }).count == originals.originals.count else {
            throw BackendContractError.identityMismatch
        }
        return .init(recordings: recordings, originals: originals, backend: backend)
    }
}

nonisolated struct OriginalUploadAcceptanceSnapshot: Sendable {
    let recordings: RecordingStoreSnapshot
    let originals: OriginalStoreSnapshot
    let backend: BackendStoreSnapshot
}

nonisolated enum OriginalUploadAcceptanceBoundary {
    /// Without a destination selector, multiple destinations are ambiguous.
    /// A later intent without its committed registration is ambiguous as well.
    static func currentRegistration(_ snapshot: BackendStoreSnapshot) -> DeviceRegistration? {
        guard let current = snapshot.registrations.last, current.isCommitted,
              (try? OriginalUploadAcceptanceValueValidation.registration(current)) != nil,
              snapshot.registrations.allSatisfy({
                  OriginalUploadAcceptanceValueValidation.exact($0.server.registration.destination, current.server.registration.destination)
              }), let intent = snapshot.registrationIntents.last, intent.isCommitted,
              snapshot.registrationIntents.allSatisfy({
                  OriginalUploadAcceptanceValueValidation.exact($0.intent.destination, current.server.registration.destination)
              }), OriginalUploadAcceptanceValueValidation.exact(intent.intent, current.server.intent),
              OriginalUploadAcceptanceValueValidation.exact(intent.commit, current.intentCommit) else { return nil }
        return current
    }

    static func candidate(_ recording: RecordingStoreEntry, state: OriginalPersistentState?) -> OriginalBinding? {
        guard let binding = state?.binding,
              OriginalUploadAcceptanceValueValidation.exact(binding.reference, recording.intent.original),
              OriginalUploadAcceptanceValueValidation.exact(binding.original.capture, recording.intent.context.capture),
              OriginalUploadAcceptanceValueValidation.exact(binding.saveRecord.intent, recording.intent),
              OriginalUploadAcceptanceValueValidation.exact(Optional(binding.saveRecord), recording.result),
              OriginalUploadAcceptanceValueValidation.exact(Optional(binding.saveCommit), recording.resultCommit) else { return nil }
        return binding
    }

    static func sameBoundary(_ before: OriginalUploadAcceptanceSnapshot, _ after: OriginalUploadAcceptanceSnapshot,
        request: OriginalUploadAcceptanceRequest) -> Bool {
        guard before.backend.storeIdentity == after.backend.storeIdentity,
              OriginalUploadAcceptanceValueValidation.exact(currentRegistration(before.backend), currentRegistration(after.backend)) else { return false }
        for target in request.targets {
            let capture = target.binding.original.capture
            let old = before.recordings.recordings.first { $0.intent.context.capture == capture }
            let new = after.recordings.recordings.first { $0.intent.context.capture == capture }
            guard old?.revision == new?.revision,
                  OriginalUploadAcceptanceValueValidation.exact(old?.intent, new?.intent),
                  OriginalUploadAcceptanceValueValidation.exact(old?.result, new?.result),
                  OriginalUploadAcceptanceValueValidation.exact(old?.resultToken, new?.resultToken) else { return false }
            let oldState = before.originals.originals.first { $0.binding.original.capture == capture }
            let newState = after.originals.originals.first { $0.binding.original.capture == capture }
            guard OriginalUploadAcceptanceValueValidation.exact(oldState?.binding, newState?.binding),
                  oldState == newState else { return false }
        }
        return true
    }
}
