import Foundation
import Testing
@testable import FrameRelay

/// Disposable bytes and published identities are explicitly S25 technical
/// fixtures. This is real disk/resolver coverage with a fake Photos boundary;
/// it proves neither PhotoKit behavior nor formal Rec.709 product eligibility.
nonisolated struct PhotoSaveFixture: Sendable {
    let rendition: RenditionFixture
    let faults: PhotoSaveFaultStore
    let identity: RegistrationStoreIdentity
    let receipt: TemporaryMediaReceipt
    let library: PhotoSaveLibrary
    let media: PhotoSaveMedia
    let coordinator: PhotoSaveCoordinator

    static func make(run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite,
                     keepPlayback: Bool = false) async throws -> Self {
        let bytes = Data((0..<4096).map { UInt8($0 % 251) })
        let rendition = try await RenditionFixture.make(run: run, content: renditionContent(bytes), candidate: candidate)
        let complete = try await rendition.complete(bytes)
        let snapshot = try await mediaSnapshot(rendition.store)
        let identity = try await rendition.store.establishRegistrationIdentity(expectedRevision: snapshot.revision, expectedIdentity: nil)
        guard case .succeeded(let usage) = await rendition.temporary.acquireUsage(complete.id,
            purpose: .photoHandoff, usageID: .init(rawValue: "s31-photo-use")) else { throw BackendContractError.unavailable }
        let receipt = try await rendition.temporary.stateFor(complete.id).receipt(for: usage)
        if !keepPlayback {
            guard await rendition.temporary.releaseUsage(complete.usage) == .succeeded(complete.id) else { throw BackendContractError.unavailable }
        }
        let faults = await PhotoSaveFaultStore(base: rendition.store)
        let library = PhotoSaveLibrary()
        let media = PhotoSaveMedia(base: rendition.temporary)
        let coordinator = PhotoSaveCoordinator(store: faults, identity: identity, temporaryMedia: media, library: library)
        return .init(rendition: rendition, faults: faults, identity: identity, receipt: receipt,
            library: library, media: media, coordinator: coordinator)
    }

    func reopenedCoordinator(store: (any MediaOperationStorePort)? = nil) -> PhotoSaveCoordinator {
        .init(store: store ?? faults, identity: identity, temporaryMedia: media, library: library)
    }

    func latest() async throws -> PhotoRegistrationRecord {
        try #require(try await mediaSnapshot(rendition.store).photoRegistrations.last)
    }

    func commitIntent(action: String = "saved-intent-only") async throws -> PhotoRegistrationRecord {
        let intent = try PhotoRegistrationIntent(operation: .init(rawValue: action),
            handoff: receipt.photoHandoff(expected: receipt.rendition))
        let snapshot = try await mediaSnapshot(rendition.store)
        let mutation = BackendStoreMutation(expectedRevision: snapshot.revision,
            change: .photo(command: intent.operation, value: .intent(intent)), expectedStoreIdentity: identity)
        guard case .committed = await rendition.store.commit(mutation) else { throw BackendContractError.notCommitted }
        return try await latest()
    }
}

actor PhotoSaveLibrary: PhotoLibraryPort {
    nonisolated static func make() -> PhotoSaveLibrary { PhotoSaveLibrary() }
    var addAuthorization: PhotoLibraryAuthorization = .notDetermined
    var readAuthorization: PhotoLibraryAuthorization = .notDetermined
    var addRequestResult: PhotoLibraryAuthorization = .authorized
    var readRequestResult: PhotoLibraryAuthorization = .authorized
    var outcome: PhotoRegistrationOutcome = .succeeded(localIdentifier: try! .init(rawValue: "s31-fixture-asset"))
    var presence: PhotoAssetPresence = .present
    var delayed = false
    var wrongIntent = false
    private var terminal: CheckedContinuation<Void, Never>?
    private(set) var additions: [PhotoLibraryAddCommand] = []
    private(set) var requests: [PhotoLibraryAccess] = []
    private(set) var lookups: [PhotoAssetIdentifier] = []
    private(set) var fileBytes: Data?
    private(set) var completed = 0

    func configure(add: PhotoLibraryAuthorization? = nil, read: PhotoLibraryAuthorization? = nil,
                   outcome: PhotoRegistrationOutcome? = nil, presence: PhotoAssetPresence? = nil,
                   delayed: Bool? = nil, wrongIntent: Bool? = nil) {
        if let add { addAuthorization = add }
        if let read { readAuthorization = read }
        if let outcome { self.outcome = outcome }
        if let presence { self.presence = presence }
        if let delayed { self.delayed = delayed }
        if let wrongIntent { self.wrongIntent = wrongIntent }
    }
    func authorizationStatus(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization {
        access == .addOnly ? addAuthorization : readAuthorization
    }
    func requestAuthorization(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization {
        requests.append(access)
        if access == .addOnly { addAuthorization = addRequestResult; return addRequestResult }
        readAuthorization = readRequestResult; return readRequestResult
    }
    func add(_ command: PhotoLibraryAddCommand) async -> PhotoRegistrationResult {
        additions.append(command)
        fileBytes = try? Data(contentsOf: command.media.url)
        if delayed { await withCheckedContinuation { terminal = $0 } }
        completed += 1
        let intent = wrongIntent
            ? try! PhotoRegistrationIntent(operation: .init(rawValue: "unrelated-sdk-result"), handoff: command.registration.intent.handoff)
            : command.registration.intent
        return .init(intent: intent, outcome: outcome)
    }
    func complete() { delayed = false; terminal?.resume(); terminal = nil }
    func lookup(_ identifier: PhotoAssetIdentifier) -> PhotoLibraryLookupResult {
        lookups.append(identifier)
        return .init(identifier: identifier, authorization: readAuthorization, presence: presence)
    }
}

actor PhotoSaveMedia: TemporaryMediaPort, TemporaryLocalMediaPort, PhotoTemporaryUsageRecoveryPort {
    let base: ManagedTemporaryMedia
    private var finishFails = false
    private var releaseBlocked = false
    private(set) var resolves = 0
    private(set) var finishes = 0
    private(set) var releases = 0
    init(base: ManagedTemporaryMedia) { self.base = base }
    func configure(finishFails: Bool = false, releaseBlocked: Bool = false) {
        self.finishFails = finishFails; self.releaseBlocked = releaseBlocked
    }
    func inspect(_ id: TemporaryMediaID) async -> BackendOutcome<TemporaryMediaReceipt> { await base.inspect(id) }
    func acquireUsage(_ id: TemporaryMediaID, purpose: TemporaryMediaPurpose, usageID: MediaUsageID) async -> BackendOutcome<TemporaryMediaUsage> {
        await base.acquireUsage(id, purpose: purpose, usageID: usageID)
    }
    func releaseUsage(_ usage: TemporaryMediaUsage) async -> BackendOutcome<TemporaryMediaID> {
        releases += 1
        return releaseBlocked ? .unknown : await base.releaseUsage(usage)
    }
    func resolvePhotoMedia(_ usage: TemporaryMediaUsage) async throws -> TemporaryLocalMedia {
        resolves += 1; return try await base.resolvePhotoMedia(usage)
    }
    func finishPhotoMedia(_ usage: TemporaryMediaUsage) async throws {
        finishes += 1
        guard !finishFails else { throw BackendContractError.unavailable }
        try await base.finishPhotoMedia(usage)
    }
    func photoUsageTerminal(_ registration: CommittedPhotoRegistrationIntent,
                            termination: PhotoUsageTermination) async throws -> PhotoUsageTerminal {
        try await base.photoUsageTerminal(registration, termination: termination)
    }
    func recoverSuccessfulPhotoUsage(_ record: PhotoRegistrationRecord) async -> BackendOutcome<TemporaryMediaID> {
        releaseBlocked ? .unknown : await base.recoverSuccessfulPhotoUsage(record)
    }
    func recoverTerminalPhotoUsage(_ record: PhotoRegistrationRecord) async -> BackendOutcome<TemporaryMediaID> {
        releaseBlocked ? .unknown : await base.recoverTerminalPhotoUsage(record)
    }
}

/// Faults surround the real common writer; an after-commit fault leaves actual
/// durable bytes for a fresh writer/reconciler to find.
@MainActor final class PhotoSaveFaultStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    enum Stage: Sendable { case intent, result, presence, releaseUsage, terminal, releaseTerminalUsage }
    private let base: any MediaDiskStore
    private var stage: Stage?
    private var afterCommit = false
    private var badReceipt = false
    private var rejected = false
    private(set) var photoCommits: [BackendStoreMutation] = []
    private(set) var lookups: [BackendStoreMutation] = []

    init(base: any MediaDiskStore) { self.base = base }
    func configure(_ stage: Stage? = nil, afterCommit: Bool = false, badReceipt: Bool = false, rejected: Bool = false) {
        self.stage = stage; self.afterCommit = afterCommit; self.badReceipt = badReceipt; self.rejected = rejected
    }
    private func matches(_ mutation: BackendStoreMutation) -> Bool {
        guard case .photo(_, let value) = mutation.change else { return false }
        return switch (stage, value) {
        case (.intent?, .intent), (.result?, .result), (.presence?, .presence), (.releaseUsage?, .releaseUsage): true
        case (.terminal?, .terminal), (.releaseTerminalUsage?, .releaseTerminalUsage): true
        default: false
        }
    }
    @MainActor func establishRegistrationIdentity(expectedRevision: UInt64, expectedIdentity: RegistrationStoreIdentity?) async throws -> RegistrationStoreIdentity {
        try await base.establishRegistrationIdentity(expectedRevision: expectedRevision, expectedIdentity: expectedIdentity)
    }
    @MainActor func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .photo = mutation.change { photoCommits.append(mutation) }
        guard matches(mutation) else { return await base.commit(mutation) }
        if rejected { return .rejected(.wrongStage) }
        if afterCommit {
            let result = await base.commit(mutation)
            guard case .committed = result else { return result }
        }
        return .unknown
    }
    @MainActor func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        lookups.append(mutation)
        if badReceipt, case .photo = mutation.change {
            return .committed(.init(key: mutation.change.key, previousRevision: mutation.expectedRevision + 1,
                committedRevision: mutation.expectedRevision + 2))
        }
        return matches(mutation) ? .unknown : await base.lookupCommit(mutation)
    }
    @MainActor func load() async -> BackendStoreLoadResult { await base.load() }
    @MainActor func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult { await base.execute(command) }
    @MainActor func loadUnfinished() async -> UnfinishedRecordingLoadResult { await base.loadUnfinished() }
    @MainActor func loadRecordings() async -> RecordingStoreLoadResult { await base.loadRecordings() }
    @MainActor func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    @MainActor func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    @MainActor func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        await base.lookupInvalidation(acknowledgement)
    }
}
