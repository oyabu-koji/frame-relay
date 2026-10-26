import Testing
@testable import FrameRelay

struct BackendEvidenceRulesTests {
    @Test func preparedPlayerAndUncommittedDistributionCannotConfirm() throws {
        let f = try BackendEvidenceFixture()
        #expect(throws: BackendContractError.wrongStage) {
            try PlaybackToken(distribution: f.distribution, session: .init(rawValue: "prepared"),
                              invalidationGeneration: .init(rawValue: 0), observation: .prepared)
        }
        let wrongReceipt = DistributionReceipt(operation: f.distribution.operation, rendition: f.rendition,
                                               registration: f.registration,
                                               commit: BackendEvidenceFixture.commit(.publication(f.distribution.operation, f.rendition)))
        #expect(throws: BackendContractError.notCommitted) {
            try PlaybackToken(distribution: wrongReceipt, session: .init(rawValue: "not-distributed"),
                              invalidationGeneration: .init(rawValue: 0), observation: .played)
        }
        let token = try f.playback()
        var state = ConfirmationState(registration: f.registration, current: f.rendition,
                                      generation: .init(rawValue: 0), revision: 10)
        let intent = try state.prepareConfirmation(operation: .init(rawValue: "explicit-single-confirm"), playback: token)
        #expect(state.validConfirmation == nil)
        #expect(throws: BackendContractError.revisionConflict) {
            try state.commitConfirmation(intent, receipt: BackendEvidenceFixture.commit(intent.key, revision: 9))
        }
        try state.commitConfirmation(intent, receipt: BackendEvidenceFixture.commit(intent.key, revision: 10))
        #expect(state.validConfirmation?.intent == intent)
    }

    @Test func oldTokenAndLocalReplayCannotRestoreCommittedInvalidation() throws {
        let f = try BackendEvidenceFixture()
        var state = try f.confirmed()
        let oldToken = try f.playback()
        var ordering = try OriginalOperationOrdering(original: f.original, invalidationGeneration: .init(rawValue: 0))
        let permit = try ordering.beginInvalidation(f.invalidation)
        let acknowledgement = try state.commitInvalidation(f.invalidation,
            receipt: BackendEvidenceFixture.commit(f.invalidation.key, revision: 1), permit: permit)
        try ordering.finishInvalidation(acknowledgement)
        #expect(state.validConfirmation == nil)
        for token in [oldToken, try f.playback(generation: 1)] {
            #expect(throws: BackendContractError.invalidated) {
                try state.prepareConfirmation(operation: .init(rawValue: "delayed-old-playback"), playback: token)
            }
        }
        // Replaying the exact durable result is idempotent; it does not resurrect confirmation.
        #expect(try state.commitInvalidation(f.invalidation, receipt: acknowledgement.commit, permit: permit) == acknowledgement)
        #expect(state.validConfirmation == nil)
    }

    @Test func mismatchedPlaybackSessionRegistrationAndReceiptDoNotCommit() throws {
        let f = try BackendEvidenceFixture()
        var state = ConfirmationState(registration: f.registration, current: f.rendition,
                                      generation: .init(rawValue: 0), revision: 0)
        let intent = try state.prepareConfirmation(operation: .init(rawValue: "confirm"), playback: f.playback())
        let anotherToken = try PlaybackToken(distribution: f.distribution, session: .init(rawValue: "other-session"),
                                            invalidationGeneration: .init(rawValue: 0), observation: .played)
        let wrong = ConfirmationIntent(operation: intent.operation, playback: anotherToken)
        #expect(throws: BackendContractError.revisionConflict) {
            try state.commitConfirmation(intent, receipt: BackendEvidenceFixture.commit(wrong.key))
        }
        let newRegistration = RegistrationIdentity(destination: f.registration.destination, id: .init(rawValue: "new-device"),
                                                   generation: .init(rawValue: 2))
        let newState = ConfirmationState(registration: newRegistration, current: f.rendition,
                                         generation: .init(rawValue: 0), revision: 0)
        #expect(newState.validConfirmation == nil)
        #expect(throws: BackendContractError.invalidated) {
            try newState.prepareConfirmation(operation: intent.operation, playback: intent.playback)
        }
    }

    @Test func cleanupUsesLastMatchingProofWithoutNetworkOrPhotosRequirement() throws {
        let f = try BackendEvidenceFixture()
        let state = try f.confirmed()
        #expect(CleanupRules.evaluate(original: f.descriptor, lastVerification: f.storedVerification(),
                                      confirmation: state, supportedSchemas: ["fixture-schema"])
                == .eligible(f.original, .init(rawValue: 0)))
        for proof in [f.storedVerification(method: .assemblyOnly(f.original.content)), f.storedVerification(committed: false)] {
            #expect(CleanupRules.evaluate(original: f.descriptor, lastVerification: proof,
                                          confirmation: state, supportedSchemas: ["fixture-schema"])
                    == .ineligible(.verificationMissing))
        }
        #expect(CleanupRules.evaluate(original: f.descriptor, lastVerification: f.storedVerification(),
                                      confirmation: state, supportedSchemas: ["different-schema"])
                == .ineligible(.verificationMissing))
        let absent = OriginalDescriptor(original: f.original, reference: f.descriptor.reference,
                                        saveResult: f.descriptor.saveResult, saveCommit: f.descriptor.saveCommit,
                                        savedReference: f.descriptor.savedReference, savedContext: f.descriptor.savedContext,
                                        presence: .absent, readiness: .ready)
        #expect(CleanupRules.evaluate(original: absent, lastVerification: f.storedVerification(),
                                      confirmation: state, supportedSchemas: ["fixture-schema"])
                == .ineligible(.originalUnavailable))
    }

    @Test func completeCoverageIdentityAndUsageAreRequiredForPhotoHandoff() throws {
        let f = try BackendEvidenceFixture()
        let partial = try f.temporary(ranges: [.init(lowerBound: 0, upperBound: 9)])
        #expect(throws: BackendContractError.ineligibleOriginal) { try partial.photoHandoff(expected: f.rendition) }
        let gap = try f.temporary(ranges: [.init(lowerBound: 0, upperBound: 4), .init(lowerBound: 5, upperBound: 10)])
        #expect(!gap.hasCompleteCoverage)
        let complete = try f.temporary(ranges: [.init(lowerBound: 5, upperBound: 10), .init(lowerBound: 0, upperBound: 6)])
        #expect(try complete.photoHandoff(expected: f.rendition).rendition == f.rendition)
        for media in [f.temporary(ranges: complete.ranges, verified: false),
                      f.temporary(ranges: complete.ranges, released: true),
                      f.temporary(ranges: complete.ranges, purpose: .playback)] {
            #expect(throws: BackendContractError.ineligibleOriginal) { try media.photoHandoff(expected: f.rendition) }
        }
        let confirmed = try f.confirmed()
        _ = f.temporary(ranges: [], released: true)
        #expect(confirmed.validConfirmation != nil)
    }

    @Test func allReaderReleaseReceiptExpiresOnNewReaderAndNewEpoch() throws {
        let f = try BackendEvidenceFixture()
        var readers = try f.readers()
        let before = try #require(readers.allReleased)
        let first = try readers.acquire(id: .init(rawValue: "reader-1"), operation: .init(rawValue: "upload"))
        let second = try readers.acquire(id: .init(rawValue: "reader-2"), operation: .init(rawValue: "hash"))
        #expect(!readers.validates(before))
        try readers.observeRelease(.init(lease: first))
        #expect(readers.allReleased == nil)
        try readers.observeRelease(.init(lease: second))
        let released = try #require(readers.allReleased)
        let restarted = try f.readers(epoch: "new-process-reconciliation")
        #expect(!restarted.validates(released))
        let unknown = OriginalReadersState(original: f.original, epoch: .init(rawValue: "new-unreconciled"),
                                           generation: .init(rawValue: 2))
        #expect(unknown.allReleased == nil)
        #expect(throws: BackendContractError.identityMismatch) { try readers.observeRelease(.init(lease: first)) }
    }
}
