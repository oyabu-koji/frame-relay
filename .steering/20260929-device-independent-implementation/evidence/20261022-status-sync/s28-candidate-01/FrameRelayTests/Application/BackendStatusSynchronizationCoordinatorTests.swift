import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct BackendStatusSynchronizationCoordinatorTests {
    @Test func explicitMetadataOperationPersistsPublicationWithoutConfirmationOrMedia() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run, names: ["status-a", "status-b"])
            let next = statusRendition(f.renditions[0].original, version: 2)
            f.remote.setManifest(next, revision: 2)
            let coordinator = f.coordinator()
            #expect(f.remote.manifestCalls.isEmpty && f.remote.afters.isEmpty)
            let report = await coordinator.synchronize()
            #expect(report.phase == .checked && report.items.count == 2)
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.publications.count == 3)
            #expect(snapshot.confirmationStates.first?.current == next)
            #expect(snapshot.confirmations.isEmpty && snapshot.outbox.isEmpty)
            #expect(f.remote.mediaCalls == 0 && f.remote.sent.isEmpty)
            #expect(f.remote.afters.count == 1 && f.remote.afters[0] == nil)
        }
    }

    @Test func onePagePerActionRetainsFailuresContinuesOtherVideosAndRepollsFromNull() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run, names: ["page-a", "page-b"])
            let a = statusInvalidation(f.renditions[0], registration: f.registration.server.registration, id: "a")
            let b = statusInvalidation(f.renditions[1], registration: f.registration.server.registration, id: "b")
            f.external.available = false
            f.remote.pages = [.succeeded(.init(records: [a], nextAfter: a.id)),
                              .unknown, .succeeded(.init(records: [b], nextAfter: nil)),
                              .succeeded(.init(records: [a], nextAfter: nil))]
            let coordinator = f.coordinator()
            let first = await coordinator.synchronize()
            #expect(first.phase == .partial && first.hasMore && first.unresolvedInvalidations == 1)
            #expect(first.items.first(where: { $0.original == b.rendition.original })?.disposition == .unchanged)
            let failedPage = await coordinator.synchronize()
            #expect(failedPage.hasMore && failedPage.unresolvedInvalidations == 1)
            let third = await coordinator.synchronize()
            #expect(third.phase == .partial && !third.hasMore && third.unresolvedInvalidations == 2)
            #expect(f.remote.afters == [nil, a.id, a.id])
            #expect(try await mediaSnapshot(f.store).invalidations.isEmpty)
            f.external.available = true
            f.remote.setManifest(f.renditions[0], revision: 2, generation: 1)
            f.remote.setManifest(f.renditions[1], revision: 2, generation: 1)
            let final = await coordinator.synchronize()
            #expect(f.remote.afters.count == 4 && f.remote.afters[3] == nil)
            #expect(final.phase == .checked && final.unresolvedInvalidations == 0)
            #expect(try await mediaSnapshot(f.store).invalidations.count == 2)
            #expect(try await mediaSnapshot(f.store).outbox.isEmpty)
            #expect(f.remote.sent.count == 2 && f.remote.mediaCalls == 0)
        }
    }

    @Test func malformedCursorCannotCreateAnAutomaticPaginationLoop() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            f.remote.pages = [.succeeded(.init(records: [], nextAfter: .init(rawValue: "unrelated-cursor")))]
            let report = await f.coordinator().synchronize()
            #expect(report.phase == .partial && !report.hasMore)
            #expect(f.remote.afters.count == 1)
            #expect(f.remote.sent.isEmpty && f.remote.mediaCalls == 0)
        }
    }

    @Test(arguments: [false, true])
    func missingPublicationReplyUsesOriginalMutationRatherThanRebasing(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let next = statusRendition(f.renditions[0].original, version: 2)
            f.remote.setManifest(next, revision: 2)
            f.store.losePublication = true; f.store.afterCommit = afterCommit; f.store.hideLookup = true
            let coordinator = f.coordinator()
            #expect(await coordinator.synchronize().phase == .partial)
            let originalMutation = try #require(f.store.mutations.last)
            _ = try await mediaCommit(f.store.base, .publication(mediaPublication(next,
                registration: f.registration.server.registration, observation: 10)))
            // A newer response must not replace the unresolved payload.
            f.remote.setManifest(statusRendition(next.original, version: 3), revision: 20)
            #expect(await coordinator.synchronize().phase == .partial)
            #expect(f.store.mutations == [originalMutation])
            #expect(f.store.lookups.last == originalMutation)
            #expect(f.remote.manifestCalls.count == 1)
            if afterCommit {
                f.store.hideLookup = false
                let recovered = await coordinator.synchronize()
                #expect(recovered.items.first?.disposition == .recorded)
                #expect(f.store.mutations == [originalMutation])
            }
        }
    }

    @Test func registrationChangeDuringAwaitCannotApplyTheOldResponse() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            f.remote.setManifest(statusRendition(f.renditions[0].original, version: 2), revision: 2)
            f.remote.onManifest = { _ in
                _ = try? await mediaRegister(f.store.base, registration: .init(destination: f.registration.server.registration.destination,
                    id: .init(rawValue: "replacement-registration"), generation: .init(rawValue: 2)))
            }
            let result = await f.coordinator().synchronize()
            #expect(result.phase == .unavailable)
            #expect(try await mediaSnapshot(f.store).publications.count == 1)
            #expect(f.store.mutations.isEmpty && f.remote.sent.isEmpty)
        }
    }

    @Test func opaqueUnicodeMismatchIsLocalToThatVideo() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run, names: ["\u{e9}", "independent"])
            let original = f.renditions[0].original
            let alias = OriginalContent(capture: .init(rawValue: "e\u{301}"), generation: original.generation, content: original.content)
            f.remote.manifests[0].1 = .succeeded(.init(current: statusRendition(alias, version: 2), revision: 2,
                invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: "video/quicktime"))
            let next = statusRendition(f.renditions[1].original, version: 2)
            f.remote.setManifest(next, revision: 2)
            let report = await f.coordinator().synchronize()
            #expect(report.phase == .partial)
            #expect(report.items.map(\.disposition) == [.unresolved, .recorded])
            #expect(try await mediaSnapshot(f.store).publications.count == 3)
            #expect(try await mediaSnapshot(f.store).confirmationStates.last?.current == next)
        }
    }

    @Test func existingConfirmationOutboxIsDeliveredWithoutCreatingAnotherAction() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let token = try publicationToken(f.renditions[0], registration: f.registration.server.registration)
            let confirmation = MediaConfirmationCoordinator(store: f.store, identity: f.identity)
            guard case .succeeded(let record) = await confirmation.confirm(token, action: .init(rawValue: "already-explicit")) else {
                throw BackendContractError.notCommitted
            }
            f.remote.loseSendReply = true
            let result = await f.coordinator().synchronize()
            #expect(result.phase == .checked)
            #expect(f.remote.sent == [.confirmation(record)])
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.confirmations == [record] && snapshot.outbox.isEmpty)
            #expect(f.remote.mediaCalls == 0)
        }
    }

    @Test func invalidatedV1CanRemainPublishedAtTheSameRevisionWhileReplacementWaits() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let record = statusInvalidation(f.renditions[0], registration: f.registration.server.registration)
            let confirmation = MediaConfirmationCoordinator(store: f.store, identity: f.identity)
            _ = await confirmation.confirm(try publicationToken(f.renditions[0], registration: record.registration),
                                           action: .init(rawValue: "explicit-before-replacement"))
            f.remote.pages = [.succeeded(.init(records: [record], nextAfter: nil))]
            f.remote.setManifest(f.renditions[0], revision: 1, generation: 1)
            let coordinator = f.coordinator()
            let first = await coordinator.synchronize()
            #expect(first.phase == .checked && first.items.first?.disposition == .unchanged)
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.publications.count == 1 && snapshot.invalidations.count == 1)
            #expect(snapshot.confirmationStates.first?.validConfirmation == nil)
            #expect(f.store.mutations.isEmpty)
            let second = await coordinator.synchronize()
            #expect(second.phase == .checked && f.store.mutations.isEmpty)
            #expect(try await mediaSnapshot(f.store).publications == snapshot.publications)
            #expect(f.remote.mediaCalls == 0)
        }
    }

    @Test func manifestAloneCannotInvalidateTheCurrentConfirmation() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let confirmation = MediaConfirmationCoordinator(store: f.store, identity: f.identity)
            guard case .succeeded(let record) = await confirmation.confirm(
                try publicationToken(f.renditions[0], registration: f.registration.server.registration),
                action: .init(rawValue: "explicit-still-valid")) else { throw BackendContractError.notCommitted }
            f.remote.setManifest(f.renditions[0], revision: 2, generation: 1)
            #expect(await f.coordinator().synchronize().phase == .partial)
            let snapshot = try await mediaSnapshot(f.store)
            #expect(snapshot.confirmationStates.first?.validConfirmation == record)
            #expect(snapshot.invalidations.isEmpty && snapshot.publications.count == 1)
        }
    }

    @Test func itemIDsIncludeExactContentAndGeneration() throws {
        let a = try publicationOriginal("\u{e9}")
        let b = OriginalContent(capture: .init(rawValue: "e\u{301}"), generation: a.generation, content: a.content)
        let c = OriginalContent(capture: a.capture, generation: .init(rawValue: 2), content: a.content)
        #expect(StatusSynchronizationItem(original: a, disposition: .unchanged).id
            != StatusSynchronizationItem(original: b, disposition: .unchanged).id)
        #expect(StatusSynchronizationItem(original: a, disposition: .unchanged).id
            != StatusSynchronizationItem(original: c, disposition: .unchanged).id)
    }

    @Test func captureBeginningDuringRequestStopsLaterWorkWithoutWaitingForAcknowledgement() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let admission = StatusSynchronizationCaptureAdmission()
            f.remote.setManifest(statusRendition(f.renditions[0].original, version: 2), revision: 2)
            f.remote.onManifest = { _ in admission.allowed = false; admission.captureAccepted = true }
            let coordinator = f.coordinator(admission: { admission.allowed })
            let result = await coordinator.synchronize()
            #expect(admission.captureAccepted)
            #expect(result.phase == .waitingForCapture)
            #expect(f.store.mutations.isEmpty && f.remote.sent.isEmpty && f.remote.mediaCalls == 0)
            let count = f.remote.afters.count
            #expect(await coordinator.synchronize().phase == .waitingForCapture)
            #expect(f.remote.afters.count == count)
        }
    }
}

@MainActor final class StatusSynchronizationCaptureAdmission {
    var allowed = true
    var captureAccepted = false
}

/// Technical fixtures use the existing actual disk stores. The remote and owner
/// inventory below are explicit test inputs, not HTTP, Log or quality evidence.
@MainActor struct StatusSynchronizationFixture {
    let store: StatusSynchronizationFaultStore
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let renditions: [RenditionIdentity]
    let remote: StatusMetadataRemote
    let external: PublicationExternalFixture
    let invalidations: MediaInvalidationCoordinator
    static func make(run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite,
                     names: [String] = ["status-known"]) async throws -> Self {
        let base = try statusSynchronizationDisk(candidate, run: run, mode: .createNew)
        let store = StatusSynchronizationFaultStore(base: base)
        let identity = try await establishRegistrationIdentity(base)
        let registrationIdentity = try await mediaRegister(base, registration: .init(
            destination: .init(rawValue: "9a3ba104-985f-4a2d-875d-d458258b9b6b"),
            id: .init(rawValue: "21088ea6-c2bc-4c21-8329-63d05bdfefcb"), generation: .init(rawValue: 1)))
        let registration = try #require(try await mediaSnapshot(base).registrations.last)
        var renditions: [RenditionIdentity] = []
        let remote = StatusMetadataRemote()
        for name in names {
            let rendition = statusRendition(try publicationOriginal(name))
            _ = try await mediaCommit(base, .publication(mediaPublication(rendition, registration: registrationIdentity)))
            renditions.append(rendition); remote.setManifest(rendition, revision: 1)
        }
        let external = PublicationExternalFixture()
        let invalidations = MediaInvalidationCoordinator(store: store, identity: identity,
            ordering: ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run)),
            scopes: RenditionScopeRegistry(leases: RenditionReadLeases(store: store)), external: external)
        return .init(store: store, identity: identity, registration: registration, renditions: renditions,
                     remote: remote, external: external, invalidations: invalidations)
    }
    func coordinator(admission: @escaping @MainActor @Sendable () -> Bool = { true }) -> BackendStatusSynchronizationCoordinator {
        .init(store: store, identity: identity, registration: registration, remote: remote,
              invalidations: invalidations, admission: admission)
    }
}

nonisolated func statusSynchronizationDisk(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
                                         mode: ExplorationStoreOpenMode, fault: RecordingStoreFault? = nil) throws -> any MediaDiskStore {
    switch candidate {
    case .atomicFile: try AtomicFileRecordingStore(run: run, mode: mode, fault: fault)
    case .sqlite: try SQLiteRecordingStore(run: run, mode: mode, fault: fault)
    }
}

/// Metadata-only known original. The unknown inspection deliberately grants no
/// normal-save, Log, cleanup or media authority, and creates no media file.
nonisolated func statusKnownOriginal(_ original: OriginalContent, store: any MediaDiskStore) async throws -> OriginalBinding {
    let f = try CaptureFixture(clip: original.capture.rawValue)
    guard case .committed(let intentReceipt) = await store.execute(.commitIntent(f.token(1), expectedRevision: 0, f.intent)) else {
        throw BackendContractError.notCommitted
    }
    var lifecycle = try RecordingSaveLifecycle(intent: f.intent, intentToken: f.token(1), revision: 0)
    try lifecycle.acceptIntentCommit(intentReceipt)
    try lifecycle.acceptRecordingEnd(context: f.context, evidence: f.end)
    try lifecycle.acceptFile(.init(context: f.context, original: f.intent.original,
        byteCount: original.content.byteCount, finalizedAt: f.time))
    _ = try lifecycle.acceptInspection(.init(context: f.context, original: f.intent.original,
        video: .unavailable(.notMeasured), audio: .unavailable(.notMeasured), format: .unavailable(.notMeasured),
        playback: .unavailable(.notMeasured), completeness: .unknown(.notMeasured)), resultToken: f.token(4))
    let result = try #require(lifecycle.resultRecord)
    guard case .committed(let receipt) = await store.execute(.commitResult(f.token(4), expectedRevision: 1, result)) else {
        throw BackendContractError.notCommitted
    }
    let binding = OriginalBinding(original: original, reference: f.intent.original, saveRecord: result, saveCommit: receipt)
    _ = try await mediaOriginalCommit(store, .bind(binding))
    return binding
}
nonisolated func statusRendition(_ original: OriginalContent, version: UInt64 = 1) -> RenditionIdentity {
    .init(original: original, inputLogIdentity: "technical-status-fixture", transformAssetIdentity: "no-formal-proof",
        transformAssetVersion: "fixture-v1", outputConfigurationIdentity: "fixture-output", conversionVersion: "fixture-conversion",
        rendition: .init(rawValue: version == 1 ? "d380d397-5a2f-4186-bd4c-e07b1df6d15e" : "00000000-0000-4000-8000-00000000000\(version)"),
        deliveryContent: original.content, publicationGeneration: .init(rawValue: version))
}
nonisolated func statusInvalidation(_ rendition: RenditionIdentity, registration: RegistrationIdentity,
                                   id: String = "status-invalidation") -> InvalidationRecord {
    .init(id: .init(rawValue: id), rendition: rendition, registration: registration, generation: .init(rawValue: 1))
}

@MainActor final class StatusSynchronizationFaultStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    let base: any MediaDiskStore
    var losePublication = false
    var afterCommit = false
    var hideLookup = false
    private(set) var mutations: [BackendStoreMutation] = []
    private(set) var lookups: [BackendStoreMutation] = []
    init(base: any MediaDiskStore) { self.base = base }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .publication = mutation.change {
            mutations.append(mutation)
            if losePublication {
                if afterCommit { _ = await base.commit(mutation) }
                return .unknown
            }
        }
        return await base.commit(mutation)
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        lookups.append(mutation)
        if case .publication = mutation.change, hideLookup { return .unknown }
        return await base.lookupCommit(mutation)
    }
    func establishRegistrationIdentity(expectedRevision: UInt64, expectedIdentity: RegistrationStoreIdentity?) async throws -> RegistrationStoreIdentity {
        try await base.establishRegistrationIdentity(expectedRevision: expectedRevision, expectedIdentity: expectedIdentity)
    }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult { await base.execute(command) }
    func loadUnfinished() async -> UnfinishedRecordingLoadResult { await base.loadUnfinished() }
    func loadRecordings() async -> RecordingStoreLoadResult { await base.loadRecordings() }
    func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> { await base.lookupInvalidation(acknowledgement) }
}

@MainActor final class StatusMetadataRemote: PublicationRemotePort {
    var manifests: [(OriginalContent, BackendOutcome<PublicationManifest>)] = []
    var pages: [BackendOutcome<PublicationInvalidationPage>] = []
    var onManifest: (@MainActor (OriginalContent) async -> Void)?
    var onInvalidations: (@MainActor () async -> Void)?
    var loseSendReply = false
    private(set) var manifestCalls: [OriginalContent] = []
    private(set) var afters: [InvalidationID?] = []
    private(set) var sent: [BackendSyncEntry] = []
    private(set) var mediaCalls = 0
    func setManifest(_ rendition: RenditionIdentity, revision: UInt64, generation: UInt64 = 0) {
        let value = BackendOutcome<PublicationManifest>.succeeded(.init(current: rendition, revision: revision,
            invalidationGeneration: .init(rawValue: generation), replacementPending: false, mediaType: "video/quicktime"))
        if let index = manifests.firstIndex(where: { PublicationStoreBoundary.exact($0.0, rendition.original) }) { manifests[index].1 = value }
        else { manifests.append((rendition.original, value)) }
    }
    func manifest(original: OriginalContent, registration: RegistrationIdentity) async -> BackendOutcome<PublicationManifest> {
        manifestCalls.append(original)
        await onManifest?(original)
        return manifests.first(where: { PublicationStoreBoundary.exact($0.0, original) })?.1 ?? .unknown
    }
    func invalidations(registration: RegistrationIdentity, after: InvalidationID?) async -> BackendOutcome<PublicationInvalidationPage> {
        afters.append(after)
        await onInvalidations?()
        return pages.isEmpty ? .succeeded(.init(records: [], nextAfter: nil)) : pages.removeFirst()
    }
    func send(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> {
        if !sent.contains(where: { PublicationStoreBoundary.exact($0, entry) }) { sent.append(entry) }
        return loseSendReply ? .unknown : .succeeded(response(entry))
    }
    func lookup(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> {
        sent.contains(where: { PublicationStoreBoundary.exact($0, entry) }) ? .succeeded(response(entry)) : .notExecuted
    }
    func distribute(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { mediaCalls += 1; return .unknown }
    func lookupDistribution(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { mediaCalls += 1; return .unknown }
    private func response(_ entry: BackendSyncEntry) -> BackendSyncResponse {
        switch entry {
        case .confirmation(let value): .confirmation(value.intent.operation)
        case .invalidation(let value): .invalidation(value.record.id)
        }
    }
}
