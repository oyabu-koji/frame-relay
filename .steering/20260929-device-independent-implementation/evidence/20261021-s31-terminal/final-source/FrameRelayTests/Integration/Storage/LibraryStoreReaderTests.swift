import Foundation
import Testing
@testable import FrameRelay

struct LibraryStoreReaderTests {
    @Test func realMovieUnknownSaveAndBindingSurviveStoreReopenWithoutMutation() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            try await bindForLibrary(run, binding: binding)
            let snapshot = try await readLibraryAfterReopen(run)
            let item = try #require(snapshot.items.first)
            #expect(snapshot.items.count == 1)
            #expect(snapshot.revision == 3)
            #expect(item.recording.result?.result == .unknown(.evidenceMissing))
            #expect(item.original == binding.original)
            #expect(item.file == .present(byteCount: binding.original.content.byteCount))
            #expect(item.requiresReconciliation)
            #expect(snapshot.history.isEmpty)
            #expect(try await readLibraryAfterReopen(run) == snapshot)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            guard case .succeeded(let state) = await store.loadOriginalState() else {
                Issue.record("Real store must remain readable"); return
            }
            #expect(state.revision == 3)
            #expect(state.originals.first?.binding == binding)
            #expect(state.originals.first?.readers.isEmpty == true)
        }
    }

    @Test func intentWithoutResultIsAnUncertainItemRatherThanEmptyLibrary() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            // Production reserves the managed destination before committing its intent.
            try await ManagedOriginalStore(run: run).reserveForRecording(fixture.intent.original)
            try await storeIntentForLibrary(run, fixture: fixture)
            let snapshot = try await readLibraryAfterReopen(run)
            #expect(snapshot.recordings.count == 1)
            #expect(snapshot.history.isEmpty)
            #expect(snapshot.items[0].file == .absent)
            #expect(snapshot.items[0].recording.result == nil)
            #expect(snapshot.items[0].requiresReconciliation)
            #expect(snapshot.revision == 1)
        }
    }

    @Test func missingReservationRemainsUnavailableInsteadOfProvingOriginalAbsence() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            // Simulate missing management metadata; do not invent a valid reserved path.
            try await storeIntentForLibrary(run, fixture: fixture)
            let snapshot = try await readLibraryAfterReopen(run)
            let item = try #require(snapshot.recordings.first)
            #expect(item.file == .unavailable(.resourceUnavailable))
            #expect(item.recording.result == nil)
            #expect(item.requiresReconciliation)
            #expect(snapshot.history.isEmpty)
            #expect(snapshot.revision == 1)
        }
    }

    @Test(arguments: [RecordingStoreLoadResult.unavailable(.evidenceMissing), .unrecognizedSchema, .corruptStore])
    func storeFailureIsNotAnEmptyLibrary(failure: RecordingStoreLoadResult) async {
        let store = LibraryReadStoreStub(recordings: failure)
        let reader = LibraryStoreReader(store: store, files: LibraryAbsentFiles())
        guard case .unavailable = await reader.loadLibrary() else {
            Issue.record("Unreadable store must not be a successful empty snapshot"); return
        }
    }

    @Test func originalStoreFailureCannotTurnDiscardHistoryIntoOrdinaryMissingFiles() async throws {
        let saved = try librarySnapshot(["one"]).items.map(\.recording)
        let store = LibraryReadStoreStub(recordings: .loaded(.init(revision: 2, recordings: saved)),
                                         originalResult: .failed(.corruptStore))
        let reader = LibraryStoreReader(store: store, files: LibraryAbsentFiles())
        #expect(await reader.loadLibrary() == .unavailable(.corruptStore))
    }

    @Test func changingRevisionsAreBoundedlyRejectedInsteadOfMixingStates() async throws {
        let saved = try librarySnapshot(["one"]).items.map(\.recording)
        let store = LibraryReadStoreStub(recordings: .loaded(.init(revision: 2, recordings: saved)),
                                         originalResult: .succeeded(.init(revision: 3, originals: [])))
        let reader = LibraryStoreReader(store: store, files: LibraryAbsentFiles())
        #expect(await reader.loadLibrary() == .unavailable(.changing))
        #expect(await store.recordingReads == 3)
    }

    @Test func commitDuringFileScanInvalidatesEarlierStoreRead() async throws {
        let saved = try librarySnapshot(["one"]).items.map(\.recording)
        let store = LibraryReadStoreStub(recordings: .loaded(.init(revision: 2, recordings: saved)),
            originalResult: .succeeded(.init(revision: 2, originals: [])),
            laterRecordings: .loaded(.init(revision: 3, recordings: saved)))
        let reader = LibraryStoreReader(store: store, files: LibraryAbsentFiles())
        #expect(await reader.loadLibrary() == .unavailable(.changing))
        #expect(await store.recordingReads == 4)
    }
}

nonisolated private func bindForLibrary(_ run: ExplorationRunDirectory, binding: OriginalBinding) async throws {
    let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
    guard case .committed = await store.commitOriginal(.init(operation: .init(rawValue: "library-bind"),
        expectedRevision: 2, change: .bind(binding))) else { throw BackendContractError.notCommitted }
}

nonisolated private func storeIntentForLibrary(_ run: ExplorationRunDirectory, fixture: CaptureFixture) async throws {
    let store = try SQLiteRecordingStore(run: run, mode: .createNew)
    guard case .committed = await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent)) else {
        throw CaptureContractError.wrongStage
    }
}

nonisolated private func readLibraryAfterReopen(_ run: ExplorationRunDirectory) async throws -> LibrarySnapshot {
    let reopened = try ExplorationRunDirectory.openExisting(at: run.url)
    let store = try SQLiteRecordingStore(run: reopened, mode: .openExisting)
    let reader = LibraryStoreReader(store: store, files: ManagedOriginalStore(run: reopened))
    guard case .loaded(let snapshot) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
    return snapshot
}

private actor LibraryReadStoreStub: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    private let recordings: RecordingStoreLoadResult
    private let originalResult: BackendOutcome<OriginalStoreSnapshot>
    private let laterRecordings: RecordingStoreLoadResult?
    private(set) var recordingReads = 0
    init(recordings: RecordingStoreLoadResult,
         originalResult: BackendOutcome<OriginalStoreSnapshot> = .succeeded(.init(revision: 0, originals: [])),
         laterRecordings: RecordingStoreLoadResult? = nil) {
        self.recordings = recordings
        self.originalResult = originalResult
        self.laterRecordings = laterRecordings
    }
    func loadRecordings() -> RecordingStoreLoadResult {
        recordingReads += 1
        return recordingReads > 1 ? (laterRecordings ?? recordings) : recordings
    }
    func loadOriginalState() -> BackendOutcome<OriginalStoreSnapshot> { originalResult }
    func load() -> BackendStoreLoadResult {
        let revision: UInt64
        if case .loaded(let snapshot) = recordings { revision = snapshot.revision } else { revision = 0 }
        return .loaded(.init(revision: revision, registrationIntents: [], registrations: [], batches: [],
            requests: [], verifications: [], confirmations: [], invalidations: [], outbox: []))
    }
    func commit(_ mutation: BackendStoreMutation) -> BackendCommitResult { fatalError("Read-only Library wrote media state") }
    func lookupCommit(_ mutation: BackendStoreMutation) -> BackendCommitResult { fatalError("Read-only Library looked up a write") }
    func execute(_ command: RecordingStoreCommand) -> RecordingStoreResult { fatalError("Read-only consumer wrote a recording") }
    func loadUnfinished() -> UnfinishedRecordingLoadResult { fatalError("Library omitted successful recordings") }
    func commitOriginal(_ mutation: OriginalStoreMutation) -> OriginalStoreCommitResult { fatalError("Read-only consumer wrote an original") }
}

private struct LibraryAbsentFiles: RecordingOriginalFilePort {
    func reserveForRecording(_ original: CaptureOriginalReference) async throws { throw BackendContractError.wrongStage }
    func observeFile(_ original: CaptureOriginalReference) async -> OriginalFileObservation { .absent }
}
