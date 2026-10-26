import Testing
@testable import FrameRelay

struct LibraryProjectionTests {
    @Test(arguments: [RecordingSaveResult.saved, .partial(.evidenceMissing), .failed(.evidenceMissing)])
    func committedFileWithoutBindingExplicitlyRequiresIdentityReconciliation(result: RecordingSaveResult) throws {
        let entry = try libraryRecording("unbound", result: result)
        let item = LibraryProjection.item(entry, file: .present(byteCount: 4096), state: nil)
        #expect(item.original == nil)
        #expect(item.requiresReconciliation)
        #expect(item.status(.original) == "原本あり・内容の対応未確定・要照合")
        #expect(item.recording.result?.result == result)
        #expect(item.removal == .none)
        #expect(!item.isDiscardHistory)
        let bound = LibraryProjection.item(entry, file: .present(byteCount: 4096), state: try libraryOriginalState(entry))
        #expect(!bound.requiresReconciliation)
        #expect(bound.status(.original) == "原本あり")
    }

    @Test(arguments: [RecordingSaveResult.saved, .partial(.evidenceMissing), .unknown(.evidenceMissing), .failed(.evidenceMissing)])
    func presenceNeverChangesHistoricalSaveResult(result: RecordingSaveResult) throws {
        let entry = try libraryRecording("synthetic-save", result: result)
        let present = LibraryProjection.item(entry, file: .present(byteCount: 4096), state: nil)
        let missing = LibraryProjection.item(entry, file: .absent, state: nil)
        #expect(present.recording.result?.result == result)
        #expect(missing.recording.result?.result == result)
        #expect(present.status(.save) == missing.status(.save))
        #expect(!missing.isDiscardHistory)
        #expect(missing.requiresReconciliation)
        #expect(missing.removal == .reconciliationRequired(nil))
        #expect(Set(present.statuses.map(\.axis)) == Set(LibraryAxis.allCases))
        #expect(present.status(.photos).contains("まだ取得できません"))
    }

    @Test func unfinishedSaveAndInaccessibleOriginalStayUncertain() throws {
        let fixture = try CaptureFixture()
        let entry = RecordingStoreEntry(intentToken: fixture.token(1), intent: fixture.intent,
                                        revision: 1, resultToken: nil, result: nil)
        let item = LibraryProjection.item(entry, file: .unavailable(.evidenceMissing), state: nil)
        #expect(item.status(.save) == "保存結果未確定・要照合")
        #expect(item.requiresReconciliation)
        #expect(!item.isDiscardHistory)
        #expect(item.recording.result == nil)
    }

    @Test(arguments: [RemovalPurpose.cleanup, .discard])
    func unresolvedRemovalNeverHidesItem(purpose: RemovalPurpose) throws {
        let entry = try libraryRecording("synthetic-pending")
        var state = try libraryOriginalState(entry)
        state.removal = .init(operation: .init(rawValue: "remove"), original: state.binding.original, purpose: purpose)
        for file: OriginalFileObservation in [.present(byteCount: 4096), .absent, .unavailable(.evidenceMissing)] {
            let item = LibraryProjection.item(entry, file: file, state: state)
            #expect(!item.isDiscardHistory)
            #expect(item.requiresReconciliation)
            #expect(item.removal == .reconciliationRequired(purpose))
        }
    }

    @Test func mismatchedBindingCannotSupplyOriginalOrDeletionSuccess() throws {
        let entry = try libraryRecording("synthetic-one")
        let unrelated = try libraryOriginalState(libraryRecording("synthetic-two"))
        let item = LibraryProjection.item(entry, file: .absent, state: unrelated)
        #expect(item.original == nil)
        #expect(item.requiresReconciliation)
        #expect(!item.isDiscardHistory)
    }

    @Test(arguments: [RemovalPurpose.cleanup, .discard])
    func onlyResolvedRemovalAndObservedAbsenceCanBeSuccessful(purpose: RemovalPurpose) throws {
        let entry = try libraryRecording("synthetic-resolved")
        var state = try libraryOriginalState(entry)
        state.resolvedRemoval = .init(operation: .init(rawValue: "resolved"), original: state.binding.original, purpose: purpose)
        state.removalResolution = .removed
        let removed = LibraryProjection.item(entry, file: .absent, state: state)
        #expect(removed.removal == .removed(purpose))
        #expect(removed.isDiscardHistory == (purpose == .discard))
        #expect(!removed.requiresReconciliation)
        #expect(removed.recording == entry)
        for file: OriginalFileObservation in [.present(byteCount: 4096), .unavailable(.evidenceMissing)] {
            let inconsistent = LibraryProjection.item(entry, file: file, state: state)
            #expect(inconsistent.removal == .reconciliationRequired(purpose))
            #expect(inconsistent.requiresReconciliation)
            #expect(!inconsistent.isDiscardHistory)
        }
        state.removalResolution = .notRemoved
        let stillPresent = LibraryProjection.item(entry, file: .present(byteCount: 4096), state: state)
        #expect(stillPresent.removal == .notRemoved(purpose))
        #expect(!stillPresent.isDiscardHistory)
        #expect(LibraryProjection.item(entry, file: .absent, state: state).requiresReconciliation)
    }
}

/// Synthetic value tests only. No claim that these values came from a real recording.
nonisolated func libraryRecording(_ capture: String, result: RecordingSaveResult = .saved) throws -> RecordingStoreEntry {
    let fixture = try CaptureFixture(clip: capture)
    let record = RecordingResultRecord(intent: fixture.intent, end: fixture.end, file: fixture.file,
                                      inspection: fixture.inspection(), result: result)
    return .init(intentToken: fixture.token(1), intent: fixture.intent, revision: 2,
                 resultToken: fixture.token(4), result: record)
}

nonisolated func libraryOriginalState(_ entry: RecordingStoreEntry) throws -> OriginalPersistentState {
    let binding = OriginalBinding(original: .init(capture: entry.intent.context.capture,
        generation: .init(rawValue: 1), content: try .init(byteCount: 4096, algorithm: "sha256", digest: String(repeating: "a", count: 64))),
        reference: entry.intent.original, saveRecord: try #require(entry.result), saveCommit: try #require(entry.resultCommit))
    return .init(binding: binding,
                 bindingCommit: .init(operation: .init(rawValue: "bind"), previousRevision: 2, committedRevision: 3))
}

nonisolated func librarySnapshot(_ captures: [String]) throws -> LibrarySnapshot {
    try .init(revision: 2, items: captures.map {
        LibraryProjection.item(try libraryRecording($0), file: .present(byteCount: 4096), state: nil)
    })
}
