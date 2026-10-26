import Foundation
import Testing
@testable import FrameRelay

struct OriginalBindingStoreTests {
    @Test(arguments: [nil, RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func actualContentBindingSurvivesReopenAndCommitInterruption(fault: RecordingStoreFault?) async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let mutation = OriginalStoreMutation(operation: .init(rawValue: "synthetic-bind"),
                                                 expectedRevision: 2, change: .bind(binding))
            let result = try await commitBindingOnce(run: run, mutation: mutation, fault: fault)
            if fault != nil { #expect(result == .unavailable(.inaccessible)) }
            let store = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            guard case .succeeded(let snapshot) = await store.loadOriginalState() else {
                Issue.record("Expected a real reopened binding store"); return
            }
            if fault == .beforeDiskCommit {
                #expect(snapshot.revision == 2)
                #expect(snapshot.originals.isEmpty)
            } else {
                #expect(snapshot.revision == 3)
                #expect(snapshot.originals.first?.binding == binding)
                #expect(snapshot.originals.first?.binding.original.generation.rawValue == 1)
                #expect(binding.saveRecord.result == .unknown(.evidenceMissing))
                #expect(await store.commitOriginal(mutation) == .committed(.init(operation: mutation.operation,
                    previousRevision: 2, committedRevision: 3)))
            }
        }
    }

    @Test func contentReplacementRevisionConflictAndForgedSaveReceiptAreRejected() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let operation = MediaOperationID(rawValue: "synthetic-bind")
            #expect(await store.commitOriginal(.init(operation: operation, expectedRevision: 0, change: .bind(binding)))
                == .rejected(.revisionConflict))
            let forged = OriginalBinding(original: binding.original, reference: binding.reference,
                saveRecord: binding.saveRecord,
                saveCommit: .init(token: binding.saveCommit.token, previousRevision: 0, committedRevision: 1))
            #expect(await store.commitOriginal(.init(operation: operation, expectedRevision: 2, change: .bind(forged)))
                == .rejected(.identityMismatch))
            let mutation = OriginalStoreMutation(operation: operation, expectedRevision: 2, change: .bind(binding))
            guard case .committed = await store.commitOriginal(mutation) else { Issue.record("Binding failed"); return }
            let before = await store.loadOriginalState()
            let changed = OriginalBinding(original: .init(capture: binding.original.capture,
                generation: .init(rawValue: 9), content: binding.original.content), reference: binding.reference,
                saveRecord: binding.saveRecord, saveCommit: binding.saveCommit)
            #expect(await store.commitOriginal(.init(operation: operation, expectedRevision: 2, change: .bind(changed)))
                == .rejected(.identityMismatch))
            #expect(await store.commitOriginal(.init(operation: .init(rawValue: "other-bind"), expectedRevision: 3,
                                                     change: .bind(changed))) == .rejected(.identityMismatch))
            #expect(await store.loadOriginalState() == before)
        }
    }

    @Test func schemaTwoRetainsResultsAndDoesNotInventContentBindings() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let fixture = try CaptureFixture()
            var document = RecordingStoreDocument()
            _ = try document.apply(.commitIntent(fixture.token(1), expectedRevision: 0, binding.saveRecord.intent))
            _ = try document.apply(.commitResult(fixture.token(4), expectedRevision: 1, binding.saveRecord))
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
            object["schema"] = 2
            object.removeValue(forKey: "originalJournal")
            let old = try JSONSerialization.data(withJSONObject: object)
            let file = run.url.appendingPathComponent("recordings.json")
            try old.write(to: file, options: .withoutOverwriting)
            let store = try AtomicFileRecordingStore(run: run, mode: .openExisting)
            let originals = try await mediaOriginalSnapshot(store)
            #expect(originals.revision == 2 && originals.originals.isEmpty && originals.logicalOriginals.isEmpty)
            #expect(try Data(contentsOf: file) == old)
            guard case .loaded(let snapshot) = await store.loadRecordings() else { Issue.record("Legacy read failed"); return }
            #expect(snapshot.recordings.first?.result == binding.saveRecord)
        }
    }

    @Test func malformedDecodedBindingDigestDoesNotBypassValidation() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let fixture = try CaptureFixture()
            var document = RecordingStoreDocument()
            _ = try document.apply(.commitIntent(fixture.token(1), expectedRevision: 0, binding.saveRecord.intent))
            _ = try document.apply(.commitResult(fixture.token(4), expectedRevision: 1, binding.saveRecord))
            _ = try document.applyOriginal(.init(operation: .init(rawValue: "bind"), expectedRevision: 2, change: .bind(binding)))
            let valid = try JSONEncoder().encode(document)
            let text = try #require(String(data: valid, encoding: .utf8))
            let corrupt = Data(text.replacingOccurrences(of: binding.original.content.digest, with: "invalid").utf8)
            #expect(throws: ExplorationStorageError.corruptStore) { try RecordingStoreDocument.decode(corrupt) }
        }
    }
}

/// Real H264 + silent PCM movie, genuine full-file hash and AV reader inspection.
/// Its unverified Log/playback/completeness remain UNKNOWN, never synthetic saved.
nonisolated func makeBindingMovie(run: ExplorationRunDirectory) async throws -> OriginalBinding {
    let fixture = try CaptureFixture()
    let store = try SQLiteRecordingStore(run: run, mode: .createNew)
    let originals = ManagedOriginalStore(run: run)
    let coordinator = OriginalSaveCoordinator(store: store, originals: originals,
        inspection: AVOriginalInspectionAdapter(originals: originals))
    #expect(await coordinator.begin(fixture.intent, token: fixture.token(1)) == .ready(fixture.receipt(fixture.token(1))))
    let url = try await originals.reservedURL(for: fixture.intent.original)
    try await SyntheticMovieFixture.write(to: url, withAudio: true)
    _ = await coordinator.recordingEnded(context: fixture.context, evidence: fixture.end)
    let digest = try await originals.digest(for: fixture.intent.original)
    let file = CaptureFileEvidence(context: fixture.context, original: fixture.intent.original,
                                   byteCount: digest.byteCount, finalizedAt: fixture.time)
    guard case .committed(let record, let receipt) = await coordinator.fileFinalized(file, resultToken: fixture.token(4)) else {
        throw CaptureContractError.evidenceMismatch
    }
    return OriginalBinding(original: .init(capture: fixture.context.capture, generation: .init(rawValue: 1),
        content: try .init(byteCount: digest.byteCount, algorithm: "sha256", digest: digest.sha256)),
        reference: fixture.intent.original, saveRecord: record, saveCommit: receipt)
}

nonisolated private func commitBindingOnce(run: ExplorationRunDirectory, mutation: OriginalStoreMutation,
                                         fault: RecordingStoreFault?) async throws -> OriginalStoreCommitResult {
    let store = try SQLiteRecordingStore(run: run, mode: .openExisting, fault: fault)
    return await store.commitOriginal(mutation)
}
