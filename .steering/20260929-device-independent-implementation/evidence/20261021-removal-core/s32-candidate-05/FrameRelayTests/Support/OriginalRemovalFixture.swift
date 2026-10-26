import Foundation
import Testing
@testable import FrameRelay

/// Disposable H264/PCM files plus explicitly synthetic saved/verification/played
/// contract inputs. This does not claim camera Log, remote or quality acceptance.
nonisolated struct OriginalRemovalFixture {
    let run: ExplorationRunDirectory
    let candidate: StorageCandidate
    let store: any MediaDiskStore
    let files: ManagedOriginalStore
    let access: ManagedOriginalAccess

    init(run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite) throws {
        self.run = run; self.candidate = candidate
        let store = try Self.open(run, candidate: candidate, mode: .createNew)
        self.store = store
        let files = ManagedOriginalStore(run: run)
        self.files = files
        access = .init(store: store, originals: files)
    }

    static func open(_ run: ExplorationRunDirectory, candidate: StorageCandidate,
                     mode: ExplorationStoreOpenMode = .openExisting) throws -> any MediaDiskStore {
        switch candidate {
        case .atomicFile: return try AtomicFileRecordingStore(run: run, mode: mode, supportedVerificationSchemas: ["s32-contract"])
        case .sqlite: return try SQLiteRecordingStore(run: run, mode: mode, supportedVerificationSchemas: ["s32-contract"])
        }
    }

    func original(_ name: String) async throws -> OriginalBinding {
        let fixture = try CaptureFixture(clip: name)
        guard case .committed(let intentCommit) = await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent)) else {
            throw BackendContractError.notCommitted
        }
        let url = try await files.reserve(original: fixture.intent.original)
        try await SyntheticMovieFixture.write(to: url, withAudio: true)
        let digest = try await files.digest(for: fixture.intent.original)
        var lifecycle = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
        try lifecycle.acceptIntentCommit(intentCommit)
        try lifecycle.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
        try lifecycle.acceptFile(.init(context: fixture.context, original: fixture.intent.original,
            byteCount: digest.byteCount, finalizedAt: fixture.time))
        // A synthetic classification input, independent of the real fixture's
        // H264 encoding. Production AV inspection is not bypassed or relabelled.
        _ = try lifecycle.acceptInspection(fixture.inspection(), resultToken: fixture.token(4))
        let record = try #require(lifecycle.resultRecord)
        #expect(record.result == .saved)
        guard case .committed(let receipt) = await store.execute(.commitResult(fixture.token(4), expectedRevision: 1, record)) else {
            throw BackendContractError.notCommitted
        }
        let binding = OriginalBinding(original: .init(capture: fixture.context.capture, generation: .init(rawValue: 1),
            content: try .init(byteCount: digest.byteCount, algorithm: "sha256", digest: digest.sha256)),
            reference: fixture.intent.original, saveRecord: record, saveCommit: receipt)
        _ = try await mediaOriginalCommit(store, .bind(binding))
        return binding
    }

    func evidence(_ binding: OriginalBinding) async throws -> (CleanupEvidenceSelection, InvalidationRecord) {
        let registration: RegistrationIdentity
        if let existing = try await mediaSnapshot(store).registrations.last { registration = existing.server.registration }
        else { registration = try await mediaRegister(store) }
        let suffix = binding.original.capture.rawValue
        let rendition = RenditionIdentity(original: binding.original, inputLogIdentity: "synthetic-log",
            transformAssetIdentity: "synthetic-transform", transformAssetVersion: "contract-v1",
            outputConfigurationIdentity: "synthetic-output", conversionVersion: "contract-v1",
            rendition: .init(rawValue: "rendition-" + suffix), deliveryContent: binding.original.content,
            publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
        let distributionOperation = MediaOperationID(rawValue: "distribution-" + suffix)
        let distribution = DistributionReceipt(operation: distributionOperation, rendition: rendition, registration: registration,
            commit: backendCommit(.distribution(distributionOperation, rendition, registration), revision: 20))
        let confirmation = ConfirmationIntent(operation: .init(rawValue: "confirmation-" + suffix),
            playback: try .init(distribution: distribution, session: .init(rawValue: "play-" + suffix),
                invalidationGeneration: .init(rawValue: 0), observation: .played))
        _ = try await mediaCommit(store, .confirmation(confirmation))
        let context = RemoteOperationContext(operation: .init(rawValue: "upload-" + suffix), registration: registration,
            target: .original(binding.original), session: .init(rawValue: "upload-session-" + suffix))
        let command = MediaOperationID(rawValue: "verification-" + suffix)
        let proof = VerificationEvidence(id: .init(rawValue: "proof-" + suffix), context: context, finalSaveCompleted: true,
            verification: .finalDestinationReadBack(binding.original.content), committed: true,
            schemaVersion: "s32-contract", observedAt: Date(timeIntervalSince1970: 1))
        _ = try await mediaCommit(store, .verification(command: command, expected: context, evidence: proof))
        return (.init(registration: registration, verificationCommand: command, confirmationOperation: confirmation.operation),
            .init(id: .init(rawValue: "invalidate-" + suffix), rendition: rendition, registration: registration,
                  generation: .init(rawValue: 1)))
    }

    func batch(_ bindings: [OriginalBinding], name: String = "cleanup-batch") throws -> OriginalRemovalBatch {
        try .init(operation: .init(rawValue: name), purpose: .cleanup,
            targets: bindings.map { .init(original: $0.original, reference: $0.reference,
                operation: .init(rawValue: name + "-" + $0.original.capture.rawValue)) }, authorization: .cleanup)
    }

    func coordinator(store override: (any MediaDiskStore)? = nil, access overrideAccess: ManagedOriginalAccess? = nil) -> CleanupCoordinator {
        let access = overrideAccess ?? self.access
        return .init(store: override ?? store,
            termination: OriginalRemovalTestTermination(access: access, store: override ?? store), execution: access)
    }
}

actor OriginalRemovalTestTermination {
    let access: ManagedOriginalAccess
    let store: any OriginalStorePort
    init(access: ManagedOriginalAccess, store: any OriginalStorePort) { self.access = access; self.store = store }
    func stopForRemoval(_ target: OriginalRemovalTarget) async -> BackendOutcome<OriginalRemovalQuiescence> {
        // Explicit test-only observations from every synthetic SDK/OS owner.
        // Never release a recorded reader simply because this fixture has none.
        guard case .succeeded(let snapshot) = await store.loadOriginalState(),
              let state = snapshot.logicalOriginals.first(where: { $0.original == target.original }),
              state.readers.isEmpty, state.mediaReaders.isEmpty else { return .inProgress }
        do { try await mediaReconcile(store, original: target.original) } catch { return .unknown }
        guard case .succeeded(let readers) = await access.reconcileReaders(target.original) else { return .inProgress }
        // These fixtures never create transport tasks; this is an explicit
        // synthetic transport producer, not production absence inference.
        return .succeeded(.init(target: target, transport: .neverStarted(.original(target.original)), readers: readers))
    }
}
extension OriginalRemovalTestTermination: OriginalRemovalTerminationPort {}

@MainActor final class OriginalRemovalFaultStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    enum Stage: Equatable, Sendable { case batch, reserve, boundary, result }
    let base: any MediaDiskStore
    var stage: Stage?
    var afterCommit = false
    var hideLookup = true
    var observationBarrier: OriginalRemovalDigestBarrier?
    init(base: any MediaDiskStore) { self.base = base }
    @MainActor func configure(_ stage: Stage?, afterCommit: Bool = false, hideLookup: Bool = true) {
        self.stage = stage; self.afterCommit = afterCommit; self.hideLookup = hideLookup
    }
    @MainActor func matches(_ change: OriginalStoreChange) -> Bool {
        switch (stage, change) {
        case (.batch?, .removalBatch), (.reserve?, .reserveCleanup), (.result?, .resolveRemoval): true
        default: false
        }
    }
    @MainActor func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult {
        guard matches(mutation.change) else { return await base.commitOriginal(mutation) }
        if afterCommit {
            let result = await base.commitOriginal(mutation)
            guard case .committed = result else { return result }
        }
        return .unavailable(.inaccessible)
    }
    @MainActor func commitRemovalObservation(_ mutation: OriginalStoreMutation,
        check: @Sendable () throws -> Void) async -> OriginalStoreCommitResult {
        if let observationBarrier { await observationBarrier.checkpoint() }
        guard matches(mutation.change) else { return await base.commitRemovalObservation(mutation, check: check) }
        if afterCommit {
            let result = await base.commitRemovalObservation(mutation, check: check)
            guard case .committed = result else { return result }
        }
        return .unavailable(.inaccessible)
    }
    @MainActor func lookupOriginalCommit(_ mutation: OriginalStoreMutation) async -> BackendOutcome<OriginalStoreCommitReceipt> {
        if matches(mutation.change), hideLookup { return .unknown }
        return await base.lookupOriginalCommit(mutation)
    }
    @MainActor func performRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        effect: @Sendable () throws -> Void) async -> BackendOutcome<RemovalResolutionReceipt> {
        if stage == .boundary {
            if afterCommit {
                let result = await base.performRemovalBoundary(boundary, effect: effect)
                guard case .succeeded = result else { return result }
            }
            return .unknown
        }
        return await base.performRemovalBoundary(boundary, effect: effect)
    }
    @MainActor func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult { await base.execute(command) }
    @MainActor func loadUnfinished() async -> UnfinishedRecordingLoadResult { await base.loadUnfinished() }
    @MainActor func loadRecordings() async -> RecordingStoreLoadResult { await base.loadRecordings() }
    @MainActor func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    @MainActor func load() async -> BackendStoreLoadResult { await base.load() }
    @MainActor func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    @MainActor func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
    @MainActor func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        await base.lookupInvalidation(acknowledgement)
    }
}

actor OriginalRemovalDigestBarrier {
    private var arrived = false
    private var resumed = false
    private var continuation: CheckedContinuation<Void, Never>?
    func checkpoint() async {
        arrived = true
        if resumed { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func wait() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !arrived {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw BackendContractError.unavailable }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    func resume() {
        resumed = true
        continuation?.resume(); continuation = nil
    }
}

actor OriginalRemovalCheckpointProbe {
    private(set) var reached = false
    func record() { reached = true }
}
