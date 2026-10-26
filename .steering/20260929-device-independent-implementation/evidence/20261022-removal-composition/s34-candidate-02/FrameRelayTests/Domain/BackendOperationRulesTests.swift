import Testing
@testable import FrameRelay

struct BackendOperationRulesTests {
    @Test func fixedBatchRequiresWiFiAndBothRegistrationCommits() throws {
        let fixture = try BackendOperationFixture()
        #expect(throws: BackendContractError.notOnWiFi) { try fixture.batch(onWiFi: false) }
        let valid = fixture.deviceRegistration
        let malformedCommits = [
            DeviceRegistration(server: valid.server,
                               intentCommit: backendCommit(.registrationIntent(.init(rawValue: "other-operation"),
                                                                                 fixture.destination), revision: 10),
                               commit: valid.commit),
            DeviceRegistration(server: valid.server, intentCommit: valid.intentCommit,
                               commit: backendCommit(valid.commit.key, revision: 9)),
            DeviceRegistration(server: valid.server, intentCommit: valid.intentCommit,
                               commit: .init(key: valid.commit.key, previousRevision: 11, committedRevision: 11))
        ]
        for registration in malformedCommits {
            #expect(!registration.isCommitted)
            #expect(throws: BackendContractError.notCommitted) { try fixture.batch(registration: registration) }
        }
        let batch = try fixture.batch()
        #expect(batch.fixedTargets == [fixture.original, fixture.secondOriginal])
        #expect(batch.requests.allSatisfy { !$0.startCommitted && !$0.canRun })
    }

    @Test func partialUnknownMissingAndUncommittedOriginalsCannotEnterBatch() throws {
        let fixture = try BackendOperationFixture()
        let ineligible = [
            fixture.descriptor(result: .partial(.resourceUnavailable)),
            fixture.descriptor(result: .unknown(.resourceUnavailable)),
            fixture.descriptor(result: .failed(.resourceUnavailable)),
            fixture.descriptor(presence: .absent), fixture.descriptor(presence: .unknown),
            fixture.descriptor(readiness: .writing), fixture.descriptor(readiness: .recovering),
            fixture.descriptor(readiness: .inaccessible), fixture.descriptor(hasCommit: false)
        ]
        for descriptor in ineligible {
            #expect(!descriptor.isTransferEligible)
            #expect(throws: BackendContractError.ineligibleOriginal) {
                try fixture.batch(originals: [fixture.descriptor(original: fixture.secondOriginal), descriptor])
            }
        }
        let normal = fixture.descriptor()
        let otherSave = fixture.descriptor(original: fixture.secondOriginal)
        let wrongCapture = OriginalDescriptor(original: normal.original, reference: normal.reference,
                                             saveResult: .saved, saveCommit: otherSave.saveCommit,
                                             savedReference: normal.savedReference, savedContext: normal.savedContext,
                                             presence: .present, readiness: .ready)
        let wrongReference = OriginalDescriptor(original: normal.original, reference: normal.reference,
                                               saveResult: .saved, saveCommit: normal.saveCommit,
                                               savedReference: .init(rawValue: "different-file"), savedContext: normal.savedContext,
                                               presence: .present, readiness: .ready)
        let wrongContext = OriginalDescriptor(original: normal.original, reference: normal.reference,
                                             saveResult: .saved, saveCommit: normal.saveCommit,
                                             savedReference: normal.savedReference,
                                             savedContext: .init(generation: .init(session: .init(rawValue: "other-session"),
                                                                                   settings: 91), capture: normal.original.capture),
                                             presence: .present, readiness: .ready)
        for descriptor in [wrongCapture, wrongReference, wrongContext] {
            #expect(!descriptor.isTransferEligible)
            #expect(throws: BackendContractError.ineligibleOriginal) { try fixture.batch(originals: [descriptor]) }
        }
    }

    @Test func batchRejectsEmptyDuplicateAndChangedTargetsWithoutPartialStart() throws {
        let fixture = try BackendOperationFixture()
        #expect(throws: BackendContractError.invalidValue) { try fixture.batch(originals: []) }
        #expect(throws: BackendContractError.invalidValue) { try fixture.batch(operations: []) }
        #expect(throws: BackendContractError.duplicateTarget) {
            try fixture.batch(originals: [fixture.descriptor(), fixture.descriptor()])
        }
        #expect(throws: BackendContractError.duplicateTarget) {
            try fixture.batch(operations: [.init(rawValue: "same"), .init(rawValue: "same")])
        }
        let changedContent = OriginalContent(capture: fixture.original.capture, generation: .init(rawValue: 8),
                                             content: fixture.original.content)
        #expect(throws: BackendContractError.duplicateTarget) {
            try fixture.batch(originals: [fixture.descriptor(), fixture.descriptor(original: changedContent)])
        }

        var batch = try fixture.batch()
        let wrongOperations = try fixture.batch(operations: [.init(rawValue: "other-0"), .init(rawValue: "other-1")])
        for receipt in [backendCommit(wrongOperations.commitKey, revision: 30),
                        backendCommit(batch.commitKey, revision: 29)] {
            #expect(throws: BackendContractError.notCommitted) { try batch.acceptCommit(receipt) }
            #expect(batch.requests.allSatisfy { !$0.startCommitted })
        }
        try batch.acceptCommit(backendCommit(batch.commitKey, revision: 30))
        #expect(batch.requests.allSatisfy { $0.startCommitted })
        let before = batch
        #expect(throws: BackendContractError.identityMismatch) {
            try batch.update(fixture.request(operation: "selected-after-start"))
        }
        let first = try #require(batch.requests.first)
        let changedRequest = MediaRequest(operation: first.operation, target: .original(changedContent),
                                          purpose: first.purpose, registration: first.registration,
                                          expectedStartRevision: first.expectedStartRevision)
        #expect(throws: BackendContractError.identityMismatch) { try batch.update(changedRequest) }
        #expect(batch == before)
    }

    @Test func requestNeedsExactStartCommitAndKnownRemoteResultBeforeAttempt() throws {
        let fixture = try BackendOperationFixture()
        var request = fixture.request()
        try request.reconcile(fixture.remoteResult(for: request, outcome: .notExecuted))
        #expect(!request.canRun)
        #expect(throws: BackendContractError.wrongStage) { try request.beginAttempt(.init(rawValue: "early")) }
        let expected = BackendCommitKey.request(request.operation, request.target, request.registration)
        let newerRegistration = RegistrationIdentity(destination: fixture.destination, id: fixture.registration.id,
                                                      generation: .init(rawValue: 4))
        let wrongKeys: [BackendCommitKey] = [
            .request(request.operation, .original(fixture.secondOriginal), request.registration),
            .request(request.operation, request.target, newerRegistration),
            .request(.init(rawValue: "other"), request.target, request.registration)
        ]
        for key in wrongKeys {
            #expect(throws: BackendContractError.notCommitted) {
                try request.acceptStartCommit(backendCommit(key, revision: 30))
            }
        }
        #expect(throws: BackendContractError.notCommitted) {
            try request.acceptStartCommit(backendCommit(expected, revision: 29))
        }
        #expect(!request.startCommitted)
        try request.acceptStartCommit(backendCommit(expected, revision: 30))
        try request.reconcile(fixture.remoteResult(for: request, outcome: .unknown))
        #expect(!request.canRun)
        try request.reconcile(fixture.remoteResult(for: request, outcome: .notExecuted))
        #expect(request.canRun)
    }

    @Test func overlappingWaitsDoNotEraseUserPauseAndEveryWaitMustClear() throws {
        let fixture = try BackendOperationFixture()
        var request = try fixture.readyRequest()
        let reasons: [MediaWaitReason] = [.wiFiUnavailable, .recording, .saving, .recovery, .authentication]
        for reason in reasons { request.setWait(reason, active: true) }
        for reason in reasons.dropLast() {
            request.setWait(reason, active: false)
            #expect(!request.canRun)
        }
        request.pause()
        request.setWait(.authentication, active: false)
        #expect(request.waits.isEmpty)
        #expect(request.intent == .paused)
        #expect(!request.canRun)
        try request.resume()
        #expect(request.canRun)
    }

    @Test func pauseAllIncludesQueuedAndEnvironmentalWaitsAndPreservesCancellation() throws {
        let fixture = try BackendOperationFixture()
        let third = try BackendOperationFixture.makeOriginal("C")
        var batch = try fixture.batch(originals: [fixture.descriptor(),
                                                  fixture.descriptor(original: fixture.secondOriginal),
                                                  fixture.descriptor(original: third)])
        try batch.acceptCommit(backendCommit(batch.commitKey, revision: batch.expectedRevision))
        var active = batch.requests[0]
        try active.reconcile(fixture.remoteResult(for: active, outcome: .notExecuted))
        try active.beginAttempt(.init(rawValue: "active-attempt"))
        try batch.update(active)
        var waiting = batch.requests[1]
        waiting.setWait(.queued, active: true)
        waiting.setWait(.wiFiUnavailable, active: true)
        try batch.update(waiting)
        var cancelled = batch.requests[2]
        cancelled.cancel()
        try batch.update(cancelled)

        batch.pauseAll()
        #expect(batch.requests.map(\.intent) == [.paused, .paused, .cancelled])
        #expect(batch.requests[0].transport == .stopRequested)
        #expect(batch.requests[1].transport == .queued)
        #expect(batch.requests[1].waits == [.queued, .wiFiUnavailable])
        #expect(batch.requests.allSatisfy { !$0.canRun })
        var waitingAfterReconnect = batch.requests[1]
        waitingAfterReconnect.setWait(.queued, active: false)
        waitingAfterReconnect.setWait(.wiFiUnavailable, active: false)
        try waitingAfterReconnect.reconcile(fixture.remoteResult(for: waitingAfterReconnect, outcome: .notExecuted))
        #expect(!waitingAfterReconnect.canRun)
    }

    @Test func resumeWaitsForMatchingRealStopAndReconciliationBeforeNewAttempt() throws {
        let fixture = try BackendOperationFixture()
        var request = try fixture.readyRequest()
        let attempt = TransferAttemptID(rawValue: "attempt-1")
        try request.beginAttempt(attempt)
        request.pause()
        try request.resume()
        #expect(request.transport == .stopRequested)
        #expect(!request.canRun)
        let wrongStop = TransportStopReceipt(operation: request.operation, attempt: .init(rawValue: "older-attempt"),
                                             target: request.target, registration: request.registration)
        #expect(throws: BackendContractError.identityMismatch) { try request.observeStop(wrongStop) }
        #expect(request.transport == .stopRequested)
        try request.observeStop(.init(operation: request.operation, attempt: attempt,
                                      target: request.target, registration: request.registration))
        #expect(!request.canRun)
        try request.reconcile(fixture.remoteResult(for: request, outcome: .unknown))
        #expect(!request.canRun)
        try request.reconcile(fixture.remoteResult(for: request, outcome: .inProgress,
                                                   session: .init(rawValue: "same-upload-session")))
        #expect(request.canRun)
        #expect(throws: BackendContractError.wrongStage) { try request.beginAttempt(attempt) }
        try request.beginAttempt(.init(rawValue: "attempt-2"))
        #expect(request.operation == .init(rawValue: "synthetic-upload"))
        #expect(request.session == .init(rawValue: "same-upload-session"))
        #expect(request.transport == .active)
    }

    @Test func lateRemoteSuccessCannotUndoCancellationOrBecomeANewOperationResult() throws {
        let fixture = try BackendOperationFixture()
        var request = try fixture.readyRequest()
        try request.beginAttempt(.init(rawValue: "cancelled-attempt"))
        request.cancel()
        let success = fixture.remoteResult(for: request, outcome: .succeeded(.init(rawValue: "saved-evidence")))
        try request.reconcile(success)
        #expect(request.intent == .cancelled)
        #expect(request.transport == .stopRequested)
        #expect(request.remote == .succeeded(.init(rawValue: "saved-evidence")))
        #expect(!request.canRun)
        #expect(throws: BackendContractError.wrongStage) { try request.resume() }
        for outcome: BackendOutcome<EvidenceID> in [.unknown, .notExecuted, .failed(.connectionUnavailable)] {
            try request.reconcile(fixture.remoteResult(for: request, outcome: outcome))
            #expect(request.remote == success.result)
        }
        var replacement = fixture.request(operation: "explicit-new-operation")
        #expect(throws: BackendContractError.identityMismatch) { try replacement.reconcile(success) }
        #expect(replacement.remote == .unknown)
        #expect(!replacement.canRun)
    }

    @Test func resultsFromOtherRegistrationContentRenditionOrSessionCannotMutateRequest() throws {
        let fixture = try BackendOperationFixture()
        var request = try fixture.readyRequest(purpose: .download, target: .rendition(fixture.current))
        let session = UploadSessionID(rawValue: "known-session")
        try request.reconcile(fixture.remoteResult(for: request, outcome: .inProgress, session: session))
        let otherRegistration = RegistrationIdentity(destination: fixture.destination, id: fixture.registration.id,
                                                      generation: .init(rawValue: 4))
        let otherDestination = RegistrationIdentity(destination: .init(rawValue: "other-destination"),
                                                     id: fixture.registration.id,
                                                     generation: fixture.registration.generation)
        let wrongContexts = [
            RemoteOperationContext(operation: .init(rawValue: "other-operation"), registration: request.registration,
                                   target: request.target, session: session),
            RemoteOperationContext(operation: request.operation, registration: otherRegistration,
                                   target: request.target, session: session),
            RemoteOperationContext(operation: request.operation, registration: otherDestination,
                                   target: request.target, session: session),
            RemoteOperationContext(operation: request.operation, registration: request.registration,
                                   target: .rendition(fixture.candidate), session: session),
            RemoteOperationContext(operation: request.operation, registration: request.registration,
                                   target: .original(fixture.secondOriginal), session: session),
            RemoteOperationContext(operation: request.operation, registration: request.registration,
                                   target: request.target, session: .init(rawValue: "other-session"))
        ]
        let before = request
        for context in wrongContexts {
            #expect(throws: BackendContractError.identityMismatch) {
                try request.reconcile(.init(context: context, observation: .init(rawValue: 3),
                                            result: .succeeded(.init(rawValue: "wrong-result"))))
            }
            #expect(request == before)
        }
    }

    @Test func endedPlaybackNeverRestartsWhenConditionsRecover() throws {
        let fixture = try BackendOperationFixture()
        var request = try fixture.readyRequest(purpose: .playback, target: .rendition(fixture.current))
        request.pause()
        request.setWait(.wiFiUnavailable, active: true)
        try request.endPlayback()
        request.setWait(.wiFiUnavailable, active: false)
        #expect(throws: BackendContractError.wrongStage) { try request.resume() }
        #expect(!request.canRun)
    }

    @Test func completedTransportIsExcludedFromPauseAllWithoutInventingSaveSuccess() throws {
        let fixture = try BackendOperationFixture()
        var batch = try fixture.batch()
        try batch.acceptCommit(backendCommit(batch.commitKey, revision: batch.expectedRevision))
        var completed = batch.requests[0]
        try completed.reconcile(fixture.remoteResult(for: completed, outcome: .notExecuted))
        let attempt = TransferAttemptID(rawValue: "completed-attempt")
        try completed.beginAttempt(attempt)
        try completed.observeCompletion(.init(operation: completed.operation, attempt: attempt,
                                               target: completed.target, registration: completed.registration))
        #expect(completed.remote == .notExecuted)
        try completed.reconcile(fixture.remoteResult(for: completed, outcome: .inProgress))
        #expect(!completed.canRun)
        #expect(throws: BackendContractError.wrongStage) {
            try completed.observeStop(.init(operation: completed.operation, attempt: attempt,
                                              target: completed.target, registration: completed.registration))
        }
        #expect(completed.transport == .completed)
        try batch.update(completed)
        batch.pauseAll()
        #expect(batch.requests[0].intent == .running)
        #expect(batch.requests[0].transport == .completed)
        #expect(batch.requests[1].intent == .paused)
        #expect(throws: BackendContractError.wrongStage) {
            try completed.beginAttempt(.init(rawValue: "would-duplicate-completed-transfer"))
        }
    }

    @Test func delayedStatusCannotRollInProgressBackToNotExecuted() throws {
        let fixture = try BackendOperationFixture()
        var request = try fixture.readyRequest()
        let delayed = fixture.remoteResult(for: request, outcome: .notExecuted, observation: 2)
        try request.reconcile(fixture.remoteResult(for: request, outcome: .inProgress, observation: 3))
        let before = request
        #expect(throws: BackendContractError.staleGeneration) { try request.reconcile(delayed) }
        #expect(request == before)
        try request.reconcile(fixture.remoteResult(for: request, outcome: .succeeded(.init(rawValue: "evidence"))))
        let succeeded = request
        #expect(throws: BackendContractError.identityMismatch) {
            try request.reconcile(fixture.remoteResult(for: request, outcome: .succeeded(.init(rawValue: "other-evidence"))))
        }
        #expect(request == succeeded)
    }

    @Test func registrationResponseLossKeepsSameLookupUntilBothCommitsCanBeReplayed() throws {
        let fixture = try BackendOperationFixture()
        let durable = fixture.deviceRegistration
        var recovery = RegistrationRecovery(revision: 10)
        #expect(recovery.action == .needsExplicitRegistration)
        try recovery.acceptIntent(fixture.registrationIntent, commit: durable.intentCommit)
        for outcome: BackendOutcome<RegistrationServerReceipt> in [
            .unknown, .inProgress, .failed(.connectionUnavailable), .notExecuted
        ] {
            try recovery.reconcile(outcome)
            #expect(recovery.action == .lookup(fixture.registrationIntent))
        }

        // Replay models a store adapter reopening its durable facts; no disk persistence is claimed here.
        var reopened = RegistrationRecovery(revision: 10)
        try reopened.acceptIntent(fixture.registrationIntent, commit: durable.intentCommit)
        #expect(reopened.action == .lookup(fixture.registrationIntent))
        try reopened.reconcile(.succeeded(durable.server))
        #expect(reopened.action == .commitServerResult(durable.server))
        #expect(reopened.registration == nil)
        try reopened.acceptRegistrationCommit(durable.commit)
        #expect(reopened.action == .use(durable))
        try reopened.acceptIntent(fixture.registrationIntent, commit: durable.intentCommit)
        try reopened.reconcile(.unknown)
        #expect(reopened.action == .use(durable))

        var ordinaryRestart = RegistrationRecovery(revision: 10)
        try ordinaryRestart.acceptIntent(fixture.registrationIntent, commit: durable.intentCommit)
        try ordinaryRestart.reconcile(.succeeded(durable.server))
        try ordinaryRestart.acceptRegistrationCommit(durable.commit)
        #expect(ordinaryRestart.registration == reopened.registration)
        #expect(ordinaryRestart.revision == 12)
    }

    @Test func mismatchedRegistrationResultOrCommitNeverBecomesUsableRegistration() throws {
        let fixture = try BackendOperationFixture()
        let durable = fixture.deviceRegistration
        var recovery = RegistrationRecovery(revision: 10)
        #expect(throws: BackendContractError.notCommitted) {
            try recovery.acceptIntent(fixture.registrationIntent,
                                      commit: backendCommit(durable.intentCommit.key, revision: 9))
        }
        #expect(recovery.action == .needsExplicitRegistration)
        try recovery.acceptIntent(fixture.registrationIntent, commit: durable.intentCommit)
        let otherIdentity = RegistrationIdentity(destination: .init(rawValue: "other-destination"),
                                                id: fixture.registration.id, generation: fixture.registration.generation)
        let wrongReceipts = [
            RegistrationServerReceipt(intent: .init(operation: .init(rawValue: "other-operation"),
                                                     destination: fixture.destination), registration: fixture.registration),
            RegistrationServerReceipt(intent: fixture.registrationIntent, registration: otherIdentity)
        ]
        for receipt in wrongReceipts {
            #expect(throws: BackendContractError.identityMismatch) { try recovery.reconcile(.succeeded(receipt)) }
            #expect(recovery.action == .lookup(fixture.registrationIntent))
        }
        try recovery.reconcile(.succeeded(durable.server))
        let nextRegistration = RegistrationIdentity(destination: fixture.destination, id: fixture.registration.id,
                                                     generation: .init(rawValue: 4))
        #expect(throws: BackendContractError.identityMismatch) {
            try recovery.reconcile(.succeeded(.init(intent: fixture.registrationIntent, registration: nextRegistration)))
        }
        #expect(throws: BackendContractError.notCommitted) {
            try recovery.acceptRegistrationCommit(backendCommit(.registration(fixture.registrationIntent.operation,
                                                                               nextRegistration), revision: 11))
        }
        #expect(recovery.registration == nil)
        #expect(recovery.action == .commitServerResult(durable.server))
    }

    @Test func unknownCapabilityVersionAndDestinationDoNotAuthorizeOperations() throws {
        let fixture = try BackendOperationFixture()
        let capabilities = BackendCapabilities(destination: fixture.destination, wireVersion: "synthetic-v1",
                                               operations: [.destinationIdentity, .registration, .registrationLookup])
        #expect(capabilities.supports([.registration, .registrationLookup], versions: ["synthetic-v1"],
                                      destination: fixture.destination))
        #expect(!capabilities.supports([.registration], versions: ["synthetic-v2"], destination: fixture.destination))
        #expect(!capabilities.supports([.registration], versions: ["synthetic-v1"],
                                       destination: .init(rawValue: "other-destination")))
        #expect(!capabilities.supports([.mediaDistribution], versions: ["synthetic-v1"], destination: fixture.destination))
    }
}
