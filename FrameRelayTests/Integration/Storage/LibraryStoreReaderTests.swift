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

    @Test(arguments: [false, true])
    func latestRemovedResultIsUnknownWhenCurrentFileCannotConfirmIt(unavailable: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("reader-removal", unknown: true)
            let url = try await fixture.files.existingURL(for: binding.reference)
            let bytes = try Data(contentsOf: url)
            let batch = try fixture.discardBatch(binding)
            guard case .succeeded = await fixture.discardCoordinator().start(batch) else { throw BackendContractError.notCommitted }
            let normal = LibraryStoreReader(store: fixture.store, files: fixture.files)
            guard case .loaded(let confirmed) = await normal.loadLibrary() else { throw BackendContractError.unavailable }
            #expect(confirmed.history.map(\.id) == [binding.original.capture])
            #expect(confirmed.items.first?.operationResults.first?.outcome == .succeeded)
            if !unavailable { try bytes.write(to: url) }
            let before = try await mediaOriginalSnapshot(fixture.store)
            let files: any RecordingOriginalFilePort
            if unavailable { files = LibraryUnavailableFiles() } else { files = fixture.files }
            let reader = LibraryStoreReader(store: fixture.store, files: files)
            guard case .loaded(let uncertain) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
            #expect(uncertain.history.isEmpty)
            #expect(uncertain.items.first?.removal == .reconciliationRequired(.discard))
            #expect(uncertain.items.first?.operationResults.first?.outcome == .unknown)
            #expect(uncertain.items.first?.requiresReconciliation == true)
            #expect(try await mediaOriginalSnapshot(fixture.store) == before)
        }
    }

    @Test(arguments: LibraryVerificationHintCase.allCases)
    func verificationHintUsesOnlyCurrentExactCommittedFinalRead(kind: LibraryVerificationHintCase) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("reader-proof")
            _ = try await fixture.evidence(binding, schema: "fr-final-read-v1")
            if kind == .oldRegistration {
                _ = try await mediaRegister(fixture.store, registration: .init(destination: .init(rawValue: "s21-destination"),
                    id: .init(rawValue: "replacement-registration"), generation: .init(rawValue: 2)))
            }
            let backend = try await mediaSnapshot(fixture.store)
            let proof = try #require(backend.verifications.last)
            let target: MediaTarget = kind == .otherGeneration
                ? .original(.init(capture: binding.original.capture, generation: .init(rawValue: 99), content: binding.original.content))
                : proof.expected.target
            let context = RemoteOperationContext(operation: proof.expected.operation, registration: proof.expected.registration,
                target: target, session: proof.expected.session)
            let evidence = VerificationEvidence(id: proof.evidence.id, context: context, finalSaveCompleted: true,
                verification: kind == .assemblyOnly ? .assemblyOnly(binding.original.content) : .finalDestinationReadBack(binding.original.content),
                committed: true, schemaVersion: kind == .unsupported ? "unsupported-final-read" : "fr-final-read-v1",
                observedAt: proof.evidence.observedAt)
            let commit = BackendCommitReceipt(key: .verification(kind == .uncommittedReceipt ? .init(rawValue: "other-command") : proof.command,
                evidence.id, context), previousRevision: proof.commit.previousRevision, committedRevision: proof.commit.committedRevision)
            let replacement = StoredVerificationEvidence(command: proof.command, expected: context, evidence: evidence, commit: commit)
            let displayBackend = BackendStoreSnapshot(revision: backend.revision, registrationIntents: backend.registrationIntents,
                registrations: backend.registrations, batches: backend.batches, requests: backend.requests, verifications: [replacement],
                confirmations: backend.confirmations, invalidations: backend.invalidations, outbox: backend.outbox)
            let recordingResult = await fixture.store.loadRecordings()
            let originals = await fixture.store.loadOriginalState()
            let reader = LibraryStoreReader(store: LibraryReadStoreStub(recordings: recordingResult,
                originalResult: originals, backend: displayBackend), files: fixture.files)
            guard case .loaded(let result) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
            let information = try #require(result.items.first?.removalReviewInformation)
            #expect(information.contains("最後の有効な保存検証："))
            if kind == .valid {
                #expect(information.contains(evidence.observedAt.formatted(date: .abbreviated, time: .standard)))
                #expect(!information.contains("保存検証：記録なし"))
            } else { #expect(information.contains("保存検証：記録なし")) }
            #expect(await fixture.store.loadRecordings() == recordingResult)
            #expect(await fixture.store.loadOriginalState() == originals)
        }
    }
}

nonisolated enum LibraryVerificationHintCase: CaseIterable, Equatable, Sendable {
    case valid, unsupported, assemblyOnly, oldRegistration, otherGeneration, uncommittedReceipt
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
    private let backend: BackendStoreSnapshot?
    private(set) var recordingReads = 0
    init(recordings: RecordingStoreLoadResult,
         originalResult: BackendOutcome<OriginalStoreSnapshot> = .succeeded(.init(revision: 0, originals: [])),
         laterRecordings: RecordingStoreLoadResult? = nil, backend: BackendStoreSnapshot? = nil) {
        self.recordings = recordings
        self.originalResult = originalResult
        self.laterRecordings = laterRecordings
        self.backend = backend
    }
    func loadRecordings() -> RecordingStoreLoadResult {
        recordingReads += 1
        return recordingReads > 1 ? (laterRecordings ?? recordings) : recordings
    }
    func loadOriginalState() -> BackendOutcome<OriginalStoreSnapshot> { originalResult }
    func load() -> BackendStoreLoadResult {
        if let backend { return .loaded(backend) }
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

private struct LibraryUnavailableFiles: RecordingOriginalFilePort {
    func reserveForRecording(_ original: CaptureOriginalReference) async throws { throw BackendContractError.wrongStage }
    func observeFile(_ original: CaptureOriginalReference) async -> OriginalFileObservation { .unavailable(.resourceUnavailable) }
}
