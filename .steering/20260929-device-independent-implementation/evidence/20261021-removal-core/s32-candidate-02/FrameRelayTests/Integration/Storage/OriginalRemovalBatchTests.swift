import Foundation
import Testing
@testable import FrameRelay

struct OriginalRemovalBatchTests {
    @Test(arguments: StorageCandidate.allCases)
    func orderedTargetsExactReplayAndResultShareOneJournal(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run, candidate: candidate)
            let a = try await fixture.original("batch-a")
            let b = try await fixture.original("batch-b")
            let (selection, _) = try await fixture.evidence(a)
            let batch = try fixture.batch([b, a])
            let before = try await mediaOriginalSnapshot(fixture.store)
            let mutation = OriginalStoreMutation(operation: batch.operation, expectedRevision: before.revision, change: .removalBatch(batch))
            guard case .committed(let commit) = await fixture.store.commitOriginal(mutation) else {
                Issue.record("Expected durable fixed batch"); return
            }
            #expect(await fixture.store.lookupOriginalCommit(mutation) == .succeeded(commit))
            #expect(await fixture.store.commitOriginal(mutation) == .committed(commit))
            let changed = try fixture.batch([a, b])
            #expect(await fixture.store.commitOriginal(.init(operation: changed.operation,
                expectedRevision: mutation.expectedRevision, change: .removalBatch(changed))) == .rejected(.identityMismatch))
            #expect(await fixture.store.lookupOriginalCommit(.init(operation: mutation.operation,
                expectedRevision: mutation.expectedRevision + 1, change: mutation.change)) == .failed(.rejected))
            let intent = batch.intent(for: batch.targets[1])
            _ = try await mediaOriginalCommit(fixture.store, .reserveCleanup(intent, selection,
                expectedInvalidation: .init(rawValue: 0), expectedAccess: .init(rawValue: 0)))
            var snapshot = try await mediaOriginalSnapshot(fixture.store)
            #expect(snapshot.removalBatches.first?.targets.map(\.target) == batch.targets)
            #expect(snapshot.removalBatches.first?.targets.map(\.status) == [.unprocessed, .reserved(intent)])
            #expect(snapshot.originals.first(where: { $0.binding == a })?.removal == intent)
            _ = try await mediaOriginalCommit(fixture.store, .resolveRemoval(intent, .notRemoved))
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: candidate)
            snapshot = try await mediaOriginalSnapshot(reopened)
            #expect(snapshot.removalBatches.first?.targets.map(\.status) == [.unprocessed, .resolved(.notRemoved)])
            #expect(snapshot.originals.first(where: { $0.binding == a })?.resolvedRemoval == intent)
            #expect(snapshot.originals.first(where: { $0.binding == a })?.removal == nil)
            #expect(await fixture.files.observeFile(a.reference) == .present(byteCount: a.original.content.byteCount))
            #expect(await fixture.files.observeFile(b.reference) == .present(byteCount: b.original.content.byteCount))
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func legacyIntentAndMismatchedBatchNeverAdmitPhysicalEffect(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run, candidate: candidate)
            let binding = try await fixture.original("legacy")
            let batch = try fixture.batch([binding])
            let intent = RemovalIntent(operation: batch.targets[0].operation, original: binding.original, purpose: .discard)
            _ = try await mediaOriginalCommit(fixture.store, .reserveRemoval(intent,
                expectedInvalidation: .init(rawValue: 0), expectedAccess: .init(rawValue: 0)))
            let snapshot = try await mediaOriginalSnapshot(fixture.store)
            let marker = run.url.appendingPathComponent("effect-must-not-run")
            let boundary = OriginalRemovalBoundary(batch: batch, target: batch.targets[0], intent: intent,
                expectedRevision: snapshot.revision, expectedInvalidation: .init(rawValue: 0),
                expectedAccess: .init(rawValue: 0), epoch: try #require(snapshot.reconciliationEpoch))
            #expect(await fixture.store.performRemovalBoundary(boundary) { try Data([1]).write(to: marker, options: .withoutOverwriting) } == .notExecuted)
            #expect(!FileManager.default.fileExists(atPath: marker.path))
            #expect(await fixture.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
        }
    }

    @Test func duplicateOrUnboundTargetsAndDiscardRiskMismatchAreRejected() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("validation")
            let batch = try fixture.batch([binding])
            #expect(throws: BackendContractError.self) {
                try OriginalRemovalBatch(operation: batch.operation, purpose: .cleanup,
                    targets: [batch.targets[0], batch.targets[0]], authorization: .cleanup)
            }
            #expect(throws: BackendContractError.self) {
                try OriginalRemovalBatch(operation: batch.operation, purpose: .discard,
                    targets: batch.targets, authorization: .cleanup)
            }
            let other = OriginalRemovalTarget(original: binding.original, reference: .init(rawValue: "not-this-original"),
                operation: batch.targets[0].operation)
            let forged = try OriginalRemovalBatch(operation: batch.operation, purpose: .cleanup, targets: [other], authorization: .cleanup)
            let before = try await mediaOriginalSnapshot(fixture.store)
            #expect(await fixture.store.commitOriginal(.init(operation: forged.operation, expectedRevision: before.revision,
                change: .removalBatch(forged))) == .rejected(.identityMismatch))
            #expect(try await mediaOriginalSnapshot(fixture.store) == before)
        }
    }

    @Test func corruptedDecodedBatchIsRejectedWithoutRepair() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run, candidate: .atomicFile)
            let binding = try await fixture.original("decoded")
            let batch = try fixture.batch([binding])
            let snapshot = try await mediaOriginalSnapshot(fixture.store)
            guard case .committed = await fixture.store.commitOriginal(.init(operation: batch.operation,
                expectedRevision: snapshot.revision, change: .removalBatch(batch))) else {
                Issue.record("Expected fixed batch"); return
            }
            let file = run.url.appendingPathComponent("recordings.json")
            let valid = try Data(contentsOf: file)
            let text = try #require(String(data: valid, encoding: .utf8))
            // Only the new batch's authorization changes; historical originals
            // and recording records are untouched and cannot repair the intent.
            let corrupted = Data(text.replacingOccurrences(of: "\"authorization\":{\"cleanup\":{}}", with: "\"authorization\":{\"discardRiskAcknowledged\":{}}").utf8)
            #expect(corrupted != valid)
            try corrupted.write(to: file, options: .atomic)
            #expect(throws: ExplorationStorageError.corruptStore) {
                try AtomicFileRecordingStore(run: run, mode: .openExisting)
            }
            #expect(try Data(contentsOf: file) == corrupted)
        }
    }
}
