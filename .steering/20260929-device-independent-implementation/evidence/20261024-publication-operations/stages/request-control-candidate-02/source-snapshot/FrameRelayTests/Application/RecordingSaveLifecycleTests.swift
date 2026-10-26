import Testing
@testable import FrameRelay

struct RecordingSaveLifecycleTests {
    @Test func fileAndInspectionAreNotSavedBeforeMatchingResultCommit() throws {
        let fixture = try CaptureFixture()
        var save = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
        #expect(throws: CaptureContractError.duplicateOrOutOfOrder) {
            try save.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
        }
        try save.acceptIntentCommit(fixture.receipt(fixture.token(1)))
        #expect(throws: CaptureContractError.duplicateOrOutOfOrder) { try save.acceptFile(fixture.file) }
        try save.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
        try save.acceptFile(fixture.file)
        #expect(save.phase == .fileFinalized)
        let command = try save.acceptInspection(fixture.inspection(), resultToken: fixture.token(2))
        #expect(save.phase == .awaitingResultCommit(.saved))
        guard case .commitResult(_, let revision, let record) = command else {
            Issue.record("Expected result commit command")
            return
        }
        #expect(revision == 1)
        #expect(record.intent.original == fixture.intent.original)
        #expect(throws: CaptureContractError.revisionConflict) {
            try save.acceptResultCommit(fixture.receipt(fixture.token(2), previous: 0))
        }
        #expect(save.phase == .awaitingResultCommit(.saved))
        try save.acceptResultCommit(fixture.receipt(fixture.token(2), previous: 1))
        #expect(save.phase == .committed(.saved))
        #expect(throws: CaptureContractError.duplicateOrOutOfOrder) {
            try save.acceptResultCommit(fixture.receipt(fixture.token(2), previous: 1))
        }
    }

    @Test func unknownAudioOrMissingAudioCannotBecomeNormalSavedFile() throws {
        let fixture = try CaptureFixture()
        let cases: [(CaptureTrackInspection, RecordingSaveResult)] = [
            (.unavailable(.apiDoesNotExpose), .unknown(.evidenceMissing)),
            (.missing, .partial(.evidenceMissing))
        ]
        for (audio, expected) in cases {
            var save = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
            try save.acceptIntentCommit(fixture.receipt(fixture.token(1)))
            try save.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
            try save.acceptFile(fixture.file)
            _ = try save.acceptInspection(fixture.inspection(audio: audio), resultToken: fixture.token(2))
            #expect(save.phase == .awaitingResultCommit(expected))
            try save.acceptResultCommit(fixture.receipt(fixture.token(2), previous: 1))
            #expect(save.phase == .committed(expected))
        }
    }

    @Test func inspectionForAnotherOriginalAndOldCommitAreRejected() throws {
        let fixture = try CaptureFixture()
        var save = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
        try save.acceptIntentCommit(fixture.receipt(fixture.token(1)))
        try save.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
        try save.acceptFile(fixture.file)
        #expect(throws: CaptureContractError.evidenceMismatch) {
            try save.acceptInspection(fixture.inspection(original: .init(rawValue: "synthetic-other-original")),
                                      resultToken: fixture.token(2))
        }
        #expect(save.phase == .fileFinalized)
        #expect(throws: CaptureContractError.evidenceMismatch) {
            try save.acceptInspection(fixture.inspection(), resultToken: fixture.token(1))
        }
        #expect(save.phase == .fileFinalized)
    }
}
