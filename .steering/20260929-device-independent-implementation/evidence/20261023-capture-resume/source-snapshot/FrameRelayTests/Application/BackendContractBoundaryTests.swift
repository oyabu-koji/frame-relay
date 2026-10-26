import Testing
@testable import FrameRelay

struct BackendContractBoundaryTests {
    @Test func registrationRecoveryUsesOnlyLoadedIntentAndRegistrationProofs() async throws {
        let f = try BackendEvidenceFixture()
        let store = FakeBackendStore()
        let intent = RegistrationIntent(operation: .init(rawValue: "durable-register"), destination: f.registration.destination)
        await store.inject(.afterCommit)
        #expect(await store.commit(.init(expectedRevision: 0, change: .registrationIntent(intent))) == .unknown)
        guard case .loaded(let interrupted) = await store.load() else { Issue.record("Expected saved registration intent"); return }
        let loadedIntent = try #require(interrupted.registrationIntents.first)
        let pending = try RegistrationRecovery(revision: interrupted.revision, savedIntent: loadedIntent,
                                               savedRegistration: interrupted.registrations.first)
        #expect(pending.action == .lookup(intent))
        let server = RegistrationServerReceipt(intent: loadedIntent.intent, registration: f.registration)
        let mutation = BackendStoreMutation(expectedRevision: interrupted.revision, change: .registration(server))
        #expect(await store.commit(mutation) == .unknown)
        guard case .loaded(let completed) = await store.load() else { Issue.record("Expected saved registration result"); return }
        let registration = try #require(completed.registrations.first)
        let restored = try RegistrationRecovery(revision: completed.revision,
                                                savedIntent: #require(completed.registrationIntents.first),
                                                savedRegistration: registration)
        #expect(restored.action == .use(registration))
        #expect(registration.server.intent == intent)
        #expect(registration.isCommitted)
        #expect(await store.lookupCommit(mutation) == .committed(registration.commit))
        #expect(completed.registrations.count == 1 && completed.registrationIntents.count == 1)
        #expect(throws: BackendContractError.notCommitted) {
            try RegistrationRecovery(revision: 0, savedIntent: loadedIntent, savedRegistration: registration)
        }
    }

    @Test func verificationCommitCanBeLoadedAndRetainsServerAndLocalProofBoundaries() async throws {
        let f = try BackendEvidenceFixture()
        let evidence = f.verification()
        let mutation = BackendStoreMutation(expectedRevision: 0,
            change: .verification(command: .init(rawValue: "save-proof"), expected: evidence.context, evidence: evidence))
        let store = FakeBackendStore()
        await store.inject(.beforeCommit)
        #expect(await store.commit(mutation) == .unknown)
        guard case .loaded(let before) = await store.load() else { Issue.record("Expected fake snapshot"); return }
        #expect(before.verifications.isEmpty)
        await store.inject(.afterCommit)
        #expect(await store.commit(mutation) == .unknown)
        guard case .loaded(let after) = await store.load() else { Issue.record("Expected saved proof"); return }
        let loaded = try #require(after.verifications.first)
        #expect(loaded.isCommitted)
        #expect(loaded.evidence == evidence)
        #expect(await store.lookupCommit(mutation) == .committed(loaded.commit))
        let confirmation = try f.confirmed()
        #expect(CleanupRules.evaluate(original: f.descriptor, lastVerification: loaded,
                                      confirmation: confirmation, supportedSchemas: ["fixture-schema"])
                == .eligible(f.original, .init(rawValue: 0)))
        #expect(CleanupRules.evaluate(original: f.descriptor, lastVerification: loaded,
                                      confirmation: confirmation, supportedSchemas: ["unrecognized-schema"])
                == .ineligible(.verificationMissing))
        let wrongContext = RemoteOperationContext(operation: evidence.context.operation, registration: f.registration,
                                                  target: .rendition(f.rendition), session: evidence.context.session)
        let wrong = BackendStoreMutation(expectedRevision: after.revision,
            change: .verification(command: .init(rawValue: "wrong-proof"), expected: wrongContext, evidence: evidence))
        #expect(await store.commit(wrong) == .rejected(.identityMismatch))
        let uncommittedServerEvidence = f.verification(committed: false)
        let otherStore = FakeBackendStore()
        _ = await otherStore.commit(.init(expectedRevision: 0,
            change: .verification(command: .init(rawValue: "uncommitted-server-proof"),
                                  expected: uncommittedServerEvidence.context, evidence: uncommittedServerEvidence)))
        guard case .loaded(let unverified) = await otherStore.load() else { Issue.record("Expected stored observation"); return }
        #expect(CleanupRules.evaluate(original: f.descriptor, lastVerification: unverified.verifications.first,
                                      confirmation: confirmation, supportedSchemas: ["fixture-schema"])
                == .ineligible(.verificationMissing))
    }

    @Test func lostCommitResponseMustBeLookedUpAndOutboxIsAtomic() async throws {
        let f = try BackendEvidenceFixture()
        let state = ConfirmationState(registration: f.registration, current: f.rendition,
                                      generation: .init(rawValue: 0), revision: 0)
        let intent = try state.prepareConfirmation(operation: .init(rawValue: "confirm"), playback: f.playback())
        let mutation = BackendStoreMutation(expectedRevision: 0, change: .confirmation(intent))
        let store = FakeBackendStore()
        await store.inject(.beforeCommit)
        #expect(await store.commit(mutation) == .unknown)
        #expect(await store.lookupCommit(mutation) == .unknown)
        guard case .loaded(let empty) = await store.load() else { Issue.record("Expected readable fake store"); return }
        #expect(empty.confirmations.isEmpty && empty.outbox.isEmpty && empty.revision == 0)
        await store.inject(.afterCommit)
        #expect(await store.commit(mutation) == .unknown)
        guard case .committed(let receipt) = await store.lookupCommit(mutation) else { Issue.record("Lost response must be reconcilable"); return }
        var restored = state
        try restored.commitConfirmation(intent, receipt: receipt)
        #expect(restored.validConfirmation != nil)
        #expect(await store.commit(mutation) == .committed(receipt))
        guard case .loaded(let snapshot) = await store.load() else { Issue.record("Expected readable fake store"); return }
        #expect(snapshot.confirmations.count == 1 && snapshot.outbox.count == 1 && snapshot.revision == 1)
        let otherPlayback = try PlaybackToken(distribution: f.distribution, session: .init(rawValue: "another-playback"),
                                             invalidationGeneration: .init(rawValue: 0), observation: .played)
        let other = BackendStoreMutation(expectedRevision: 1,
            change: .confirmation(.init(operation: intent.operation, playback: otherPlayback)))
        #expect(await store.commit(other) == .rejected(.identityMismatch))
        #expect(await store.lookupCommit(other) == .rejected(.identityMismatch))
    }

    @Test func unknownSchemaAndCorruptionNeverLoadAsAnEmptyStore() async throws {
        for failure: BackendFailure in [.unknownSchema, .corruptStore, .inaccessible, .capacity] {
            let store = FakeBackendStore()
            await store.makeUnreadable(failure)
            #expect(await store.load() == .unavailable(failure))
        }
    }

    @Test func invalidationCannotAckBeforeCommitAndRemainsInvalidAfterLostResponse() async throws {
        let f = try BackendEvidenceFixture()
        var state = ConfirmationState(registration: f.registration, current: f.rendition,
                                      generation: .init(rawValue: 0), revision: 0)
        var ordering = try OriginalOperationOrdering(original: f.original, invalidationGeneration: .init(rawValue: 0))
        let permit = try ordering.beginInvalidation(f.invalidation)
        let mutation = BackendStoreMutation(expectedRevision: 0, change: .invalidation(f.invalidation, permit))
        let store = FakeBackendStore()
        await store.inject(.beforeCommit)
        #expect(await store.commit(mutation) == .unknown)
        #expect(state.invalidation == nil)
        await store.inject(.afterCommit)
        #expect(await store.commit(mutation) == .unknown)
        guard case .committed(let receipt) = await store.lookupCommit(mutation) else { Issue.record("Expected committed tombstone"); return }
        let acknowledgement = try state.commitInvalidation(f.invalidation, receipt: receipt, permit: permit)
        try ordering.finishInvalidation(acknowledgement)
        #expect(acknowledgement.isCommitted)
        #expect(state.validConfirmation == nil)
        guard case .loaded(let snapshot) = await store.load() else { Issue.record("Expected fake snapshot"); return }
        #expect(snapshot.invalidations == [acknowledgement])
        #expect(snapshot.outbox == [.invalidation(acknowledgement)])
    }

    @Test func requestedStopActualStopAndHandleReleaseAreThreeDifferentBoundaries() async throws {
        let f = try BackendEvidenceFixture()
        let access = FakeBackendOriginalAccess(descriptor: f.descriptor, readers: try f.readers())
        let operation = MediaOperationID(rawValue: "upload")
        guard case .succeeded(let reader) = await access.acquireRead(f.original, operation: operation,
                                                                   leaseID: .init(rawValue: "reader")) else {
            Issue.record("Expected fake read lease"); return
        }
        let gate = MediaGateLease(operation: operation, attempt: .init(rawValue: "attempt"),
                                  target: .original(f.original), registration: f.registration, generation: 1)
        let transport = FakeBackendTransport()
        await transport.requestStop(gate)
        #expect(await transport.observeStop(gate) == .inProgress)
        #expect(await access.releaseRead(reader) == .inProgress)
        #expect(await access.reconcileReaders(f.original) == .inProgress)
        let stop = TransportStopReceipt(operation: operation, attempt: gate.attempt, target: gate.target,
                                        registration: gate.registration)
        await transport.observeTaskStopped(stop)
        #expect(await transport.observeStop(gate) == .succeeded(stop))
        #expect(await access.reconcileReaders(f.original) == .inProgress)
        try await access.observeHandleClosed(reader)
        guard case .succeeded(let released) = await access.reconcileReaders(f.original) else {
            Issue.record("Expected all readers released after actual close"); return
        }
        #expect(released.original == f.original)
    }

    @Test func invalidationFirstBlocksCleanupAndRemovalFirstDefersAckThroughRecovery() async throws {
        let f = try BackendEvidenceFixture()
        let readers = try f.readers()
        let released = try #require(readers.allReleased)
        let stopped = TransportQuiescence.neverStarted(.original(f.original))
        let boundary = RemovalBoundaryRequest(intent: f.removal, eligibility: .eligible(f.original, .init(rawValue: 0)),
                                              stopped: stopped, expectedTransport: stopped, released: released, readers: readers)
        let first = FakeBackendRemovalConsumer(ordering: try .init(original: f.original, invalidationGeneration: .init(rawValue: 0)))
        guard case .succeeded(let permit) = await first.reserveInvalidation(f.invalidation) else {
            Issue.record("Expected invalidation reservation"); return
        }
        var confirmed = try f.confirmed()
        let acknowledgement = try confirmed.commitInvalidation(f.invalidation,
            receipt: BackendEvidenceFixture.commit(f.invalidation.key, revision: 1), permit: permit)
        #expect(await first.finishInvalidation(acknowledgement) == .succeeded(f.invalidation.id))
        #expect(await first.reserveRemoval(boundary) == .failed(.rejected))

        let second = FakeBackendRemovalConsumer(ordering: try .init(original: f.original, invalidationGeneration: .init(rawValue: 0)))
        #expect(await second.reserveRemoval(boundary) == .succeeded(f.removal))
        #expect(await second.reserveInvalidation(f.invalidation) == .inProgress)
        for result: BackendOutcome<RemovalResolutionReceipt> in [.unknown, .failed(.inaccessible), .notExecuted] {
            #expect(await second.reconcileRemoval(f.removal, result: result) == .unknown)
            #expect(await second.reserveInvalidation(f.invalidation) == .inProgress)
        }
        let restored = FakeBackendRemovalConsumer(ordering: try .init(original: f.original,
            invalidationGeneration: .init(rawValue: 0), unresolvedRemoval: f.removal))
        #expect(await restored.reserveInvalidation(f.invalidation) == .inProgress)
        let resolved = RemovalResolutionReceipt(intent: f.removal, resolution: .notRemoved)
        #expect(await restored.reconcileRemoval(f.removal, result: .succeeded(resolved)) == .succeeded(f.removal))
        guard case .succeeded = await restored.reserveInvalidation(f.invalidation) else {
            Issue.record("Invalidation may proceed only after conclusive removal reconciliation"); return
        }
    }
}
