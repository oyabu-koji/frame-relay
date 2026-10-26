import Foundation
import Testing
@testable import FrameRelay

struct LibraryPhotoProjectionTests {
    @Test(arguments: [PhotoRegistrationOutcome.succeeded(localIdentifier: nil),
                      .unknown(localIdentifier: nil), .failed(.rejected), .notAttempted(.authorizationRequired)])
    func historicalAdditionAndLastPresenceAreIndependent(outcome: PhotoRegistrationOutcome) throws {
        let entry = try libraryRecording("photos-independent")
        var record = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture, outcome: outcome)
        if case .succeeded = outcome {
            let identifier = try PhotoAssetIdentifier(rawValue: "fixture-exact-identifier")
            record = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture,
                outcome: .succeeded(localIdentifier: identifier))
            record.presenceObservations = [try libraryPhotoObservation(record,
                authorization: .authorized, presence: .notFound)]
        }
        let item = LibraryProjection.item(entry, file: .present(byteCount: 4096),
            state: try libraryOriginalState(entry), photoRegistrations: [record])
        #expect(item.recording == entry)
        #expect(item.status(.save) == "正常保存")
        #expect(item.status(.original) == "原本あり")
        #expect(item.status(.photos).contains(item.photoRegistrations[0].registrationResult))
        #expect(item.status(.photoPresence).contains(item.photoRegistrations[0].presenceResult))
        #expect(item.photoRegistrations[0].record.outcome == record.outcome)
        #expect(!item.isDiscardHistory)
        if case .succeeded = outcome {
            #expect(item.status(.photos).contains("過去の登録成功"))
            #expect(item.status(.photoPresence).contains("未発見"))
            #expect(item.status(.photoPresence).contains("未保存とは判定できません"))
        }
    }

    @Test(arguments: [PhotoLibraryAuthorization.authorized, .limited, .denied, .restricted, .unknown])
    func permissionAndNotFoundNeverRewriteAnUnknownAddition(authorization: PhotoLibraryAuthorization) throws {
        let identifier = try PhotoAssetIdentifier(rawValue: "fixture-known-photo")
        var record = try libraryPhotoFixtureRecord(outcome: .unknown(localIdentifier: identifier))
        let presence: PhotoAssetPresence = authorization == .authorized || authorization == .limited ? .notFound : .unavailable
        record.presenceObservations = [try libraryPhotoObservation(record, authorization: authorization, presence: presence)]
        let row = LibraryPhotoRegistration(record: record, isLatestAttempt: true)
        #expect(row.registrationResult.contains("結果不明"))
        #expect(row.requiresReconciliation)
        #expect(row.canReconcile)
        #expect(row.reconciliationReason?.contains("追加結果が未確定") == true)
        switch authorization {
        case .authorized: #expect(row.presenceResult.contains("読取可能な範囲で未発見"))
        case .limited: #expect(row.presenceResult.contains("限定された読取範囲で未発見"))
        case .denied: #expect(row.presenceResult.contains("読み取り拒否"))
        case .restricted: #expect(row.presenceResult.contains("読み取り制限"))
        case .unknown: #expect(row.presenceResult.contains("読み取り権限が不明"))
        default: Issue.record("Unexpected test authorization")
        }
        #expect(record.outcome == .unknown(localIdentifier: identifier))
    }

    @Test func noIdentifierExplainsWhyReadPermissionCannotResolveCorrespondence() throws {
        let record = try libraryPhotoFixtureRecord(outcome: .succeeded(localIdentifier: nil))
        let row = LibraryPhotoRegistration(record: record, isLatestAttempt: true)
        #expect(row.registrationResult == "過去の登録成功")
        #expect(row.presenceResult.contains("対応不明"))
        #expect(row.reconciliationUnavailableReason?.contains("識別情報が保存されていない") == true)
        #expect(!row.canReconcile)
        #expect(!row.requiresReconciliation)
    }

    @Test func successfulAdditionDoesNotRequireReadPermissionToRemainSuccessful() throws {
        let entry = try libraryRecording("photo-success-add-only")
        let identifier = try PhotoAssetIdentifier(rawValue: "successful-add-only-identifier")
        let record = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture,
            outcome: .succeeded(localIdentifier: identifier))
        let item = LibraryProjection.item(entry, file: .present(byteCount: 4096),
            state: try libraryOriginalState(entry), photoRegistrations: [record])
        #expect(!item.requiresReconciliation)
        #expect(item.status(.photos).contains("過去の登録成功"))
        #expect(item.status(.photoPresence).contains("存在は未照合"))
        #expect(item.photoRegistrations[0].canReconcile)
    }

    @Test func versionsRemainWithTheirCaptureAndOnlyLatestAttemptCanBeReconciled() throws {
        let entry = try libraryRecording("photos-exact-capture")
        let identifier = try PhotoAssetIdentifier(rawValue: "fixture-first-photo")
        let first = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture,
            version: "version-one", operation: "first", outcome: .failed(.rejected))
        let retry = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture,
            version: "version-one", operation: "retry", outcome: .unknown(localIdentifier: identifier))
        let second = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture,
            version: "version-two", operation: "second", outcome: .succeeded(localIdentifier: identifier))
        let unrelated = try libraryPhotoFixtureRecord(capture: .init(rawValue: "another-capture"),
            version: "version-one", outcome: .unknown(localIdentifier: identifier))
        let rows = LibraryPhotoRegistration.project([first, unrelated, retry, second], capture: entry.intent.context.capture)
        #expect(rows.map(\.id.rawValue) == ["first", "retry", "second"])
        #expect(rows.map(\.isLatestAttempt) == [false, true, true])
        #expect(rows.map(\.key.rendition.rawValue) == ["version-one", "version-one", "version-two"])
        #expect(rows[0].reconciliationReason == nil)
        #expect(rows[1].canReconcile && rows[2].canReconcile)
        let item = LibraryProjection.item(entry, file: .absent, state: nil,
            photoRegistrations: [first, unrelated, retry, second])
        #expect(item.photoRegistrations == rows)
        #expect(item.status(.photos).contains("version-two"))
        #expect(!item.status(.photos).contains("another-capture"))
    }

    @Test func backendReadFailureAndRevisionMismatchCannotAppearAsNoPhotoRecords() async throws {
        let store = try LibraryPhotoReadStore(backendFailure: .corruptStore)
        let reader = LibraryStoreReader(store: store, files: LibraryPhotoAbsentFiles())
        #expect(await reader.loadLibrary() == .unavailable(.corruptStore))
        await store.setBackendFailure(nil)
        await store.setBackendRevision(5)
        #expect(await reader.loadLibrary() == .unavailable(.changing))
        #expect(await store.writes == 0)
    }

    @Test func commonRevisionIncludesPhotoRecordsWithoutAnAuthorizationDependency() async throws {
        let store = try LibraryPhotoReadStore()
        let reader = LibraryStoreReader(store: store, files: LibraryPhotoAbsentFiles())
        guard case .loaded(let snapshot) = await reader.loadLibrary() else {
            Issue.record("Consistent common-writer snapshot was not loaded"); return
        }
        #expect(snapshot.revision == 4)
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items[0].photoRegistrations.count == 1)
        #expect(snapshot.items[0].status(.photos).contains("結果不明"))
        #expect(await store.writes == 0)
    }

    @MainActor @Test func refreshAndRecreationNeverReconcileAndExplicitResultDoesNotInventHistory() async throws {
        let entry = try libraryRecording("photo-model")
        let identifier = try PhotoAssetIdentifier(rawValue: "fixture-model-photo")
        let record = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture,
            outcome: .unknown(localIdentifier: identifier))
        let item = LibraryProjection.item(entry, file: .present(byteCount: 4096),
            state: try libraryOriginalState(entry), photoRegistrations: [record])
        let snapshot = LibrarySnapshot(revision: 4, items: [item])
        let reader = LibraryPhotoMemoryReader(snapshot: snapshot)
        let photos = LibraryPhotoReconciliationSpy(result: .succeeded(record))
        let model = LibraryModel(reader: reader, photos: photos)
        await model.refresh()
        await model.refresh()
        let recreated = LibraryModel(reader: reader, photos: photos)
        await recreated.refresh()
        #expect(await photos.calls.isEmpty)
        let photo = try #require(model.item(item.id)?.photoRegistrations.first)
        #expect(model.canReconcilePhotos(photo, capture: item.id))
        await model.reconcilePhotos(photo, capture: item.id)
        #expect(await photos.calls.map(\.intent) == [record.registration.intent])
        #expect(model.item(item.id)?.photoRegistrations.first?.registrationResult.contains("結果不明") == true)
        #expect(model.snapshot == snapshot)
        #expect(model.photoReconciliationMessages[photo.id]?.contains("照合結果を記録") == true)
    }

    @MainActor @Test func missingIdentifierAndStaleDisplayedAttemptCannotRequestReadAccess() async throws {
        let entry = try libraryRecording("photo-no-id")
        let record = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture,
            outcome: .unknown(localIdentifier: nil))
        let item = LibraryProjection.item(entry, file: .present(byteCount: 4096),
            state: try libraryOriginalState(entry), photoRegistrations: [record])
        let spy = LibraryPhotoReconciliationSpy(result: .unknown)
        let reader = LibraryPhotoMemoryReader(snapshot: .init(revision: 4, items: [item]))
        let model = LibraryModel(reader: reader, photos: spy)
        await model.refresh()
        let photo = try #require(model.item(item.id)?.photoRegistrations.first)
        await model.reconcilePhotos(photo, capture: item.id)
        #expect(await spy.calls.isEmpty)
        let identifier = try PhotoAssetIdentifier(rawValue: "stale-fixture-identifier")
        let stale = LibraryPhotoRegistration(record: try libraryPhotoFixtureRecord(capture: item.id,
            outcome: .unknown(localIdentifier: identifier)), isLatestAttempt: true)
        await model.reconcilePhotos(stale, capture: item.id)
        #expect(await spy.calls.isEmpty)
    }
}

/// Synthetic presentation fixtures, never injected into production data.
nonisolated func libraryPhotoFixtureRecord(capture: CaptureID = .init(rawValue: "photo-fixture"),
    version: String = "fixture-v1", operation: String = "fixture-photo-operation",
    outcome: PhotoRegistrationOutcome?) throws -> PhotoRegistrationRecord {
    let content = try ContentIdentity(byteCount: 4096, algorithm: "sha256", digest: String(repeating: "a", count: 64))
    let rendition = RenditionIdentity(original: .init(capture: capture, generation: .init(rawValue: 1), content: content),
        inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "no-quality-claim", transformAssetVersion: "fixture-v1",
        outputConfigurationIdentity: "fixture-output", conversionVersion: "fixture-conversion",
        rendition: .init(rawValue: version), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
    let media = TemporaryMediaID(rawValue: "fixture-photo-media-" + operation)
    let usage = TemporaryMediaUsage(id: .init(rawValue: "fixture-photo-usage-" + operation), purpose: .photoHandoff,
        media: media, epoch: .init(rawValue: "fixture-photo-epoch"))
    let intent = try PhotoRegistrationIntent(operation: .init(rawValue: operation), handoff: .init(media: media,
        rendition: rendition, capturedAt: Date(timeIntervalSince1970: 1_600_000_123), usage: usage))
    let lease = MediaReadLease(id: .init(rawValue: "fixture-photo-lease-" + operation), target: .rendition(rendition),
        operation: intent.operation, registration: .init(destination: .init(rawValue: "fixture-destination"),
            id: .init(rawValue: "fixture-registration"), generation: .init(rawValue: 1)),
        context: .temporary(media, usage.id), epoch: try #require(usage.epoch), accessGeneration: .init(rawValue: 1))
    let commit = BackendCommitReceipt(key: .photo(intent.operation, intent.key), previousRevision: 2, committedRevision: 3)
    var record = PhotoRegistrationRecord(registration: .init(intent: intent,
        mediaUse: .init(usage: usage, lease: lease, owner: "fixture-owner"), commit: commit))
    if let outcome {
        let command = MediaOperationID(rawValue: "fixture-result-" + operation)
        record.results = [.init(command: command, result: .init(intent: intent, outcome: outcome),
            commit: .init(key: .photo(command, intent.key), previousRevision: 3, committedRevision: 4))]
    }
    return record
}

nonisolated private func libraryPhotoObservation(_ record: PhotoRegistrationRecord,
    authorization: PhotoLibraryAuthorization, presence: PhotoAssetPresence) throws -> StoredPhotoPresenceObservation {
    let command = MediaOperationID(rawValue: "fixture-presence")
    return try .init(command: command,
        observation: .init(intent: record.registration.intent, generation: 1, identifier: record.localIdentifier,
            authorization: authorization, presence: presence),
        commit: .init(key: .photo(command, record.registration.intent.key), previousRevision: 4, committedRevision: 5))
}

private actor LibraryPhotoReadStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    let entry: RecordingStoreEntry
    let photo: PhotoRegistrationRecord
    private var backendFailure: BackendFailure?
    private var backendRevision: UInt64 = 4
    private(set) var writes = 0
    init(backendFailure: BackendFailure? = nil) throws {
        entry = try libraryRecording("photos-common-writer")
        photo = try libraryPhotoFixtureRecord(capture: entry.intent.context.capture,
            outcome: .unknown(localIdentifier: nil))
        self.backendFailure = backendFailure
    }
    func setBackendFailure(_ value: BackendFailure?) { backendFailure = value }
    func setBackendRevision(_ value: UInt64) { backendRevision = value }
    func loadRecordings() -> RecordingStoreLoadResult { .loaded(.init(revision: 4, recordings: [entry])) }
    func loadOriginalState() -> BackendOutcome<OriginalStoreSnapshot> { .succeeded(.init(revision: 4, originals: [])) }
    func load() -> BackendStoreLoadResult {
        if let backendFailure { return .unavailable(backendFailure) }
        return .loaded(.init(revision: backendRevision, registrationIntents: [], registrations: [], batches: [],
            requests: [], verifications: [], confirmations: [], invalidations: [], outbox: [], photoRegistrations: [photo]))
    }
    func execute(_ command: RecordingStoreCommand) -> RecordingStoreResult { writes += 1; fatalError("Library must not write") }
    func loadUnfinished() -> UnfinishedRecordingLoadResult { fatalError("Library must load all records") }
    func commitOriginal(_ mutation: OriginalStoreMutation) -> OriginalStoreCommitResult { writes += 1; fatalError("Library must not write") }
    func commit(_ mutation: BackendStoreMutation) -> BackendCommitResult { writes += 1; return .unknown }
    func lookupCommit(_ mutation: BackendStoreMutation) -> BackendCommitResult { writes += 1; return .unknown }
}

private struct LibraryPhotoAbsentFiles: RecordingOriginalFilePort {
    func reserveForRecording(_ original: CaptureOriginalReference) async throws { throw BackendContractError.wrongStage }
    func observeFile(_ original: CaptureOriginalReference) async -> OriginalFileObservation { .absent }
}

private actor LibraryPhotoMemoryReader: LibraryReadPort {
    let snapshot: LibrarySnapshot
    init(snapshot: LibrarySnapshot) { self.snapshot = snapshot }
    func loadLibrary() -> LibraryLoadResult { .loaded(snapshot) }
}

private actor LibraryPhotoReconciliationSpy: LibraryPhotoReconciliationPort {
    let result: BackendOutcome<PhotoRegistrationRecord>
    private(set) var calls: [(intent: PhotoRegistrationIntent, action: MediaOperationID)] = []
    init(result: BackendOutcome<PhotoRegistrationRecord>) { self.result = result }
    func reconcile(_ intent: PhotoRegistrationIntent, action: MediaOperationID) -> BackendOutcome<PhotoRegistrationRecord> {
        calls.append((intent: intent, action: action)); return result
    }
}
