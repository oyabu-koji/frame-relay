import Foundation
import Testing
@testable import FrameRelay

struct MediaStoreRequestPersistenceTests {
    @Test func overlappingWaitsAndAttemptsSurviveReopenWithoutTreatingCompletionAsVerification() async throws {
        try await withStorageRun { run in
            let fixture = try RequestStoreFixture()
            try await prepareRequestStore(run, fixture: fixture)
            let request = fixture.request()
            _ = try await requireRequestCommit(run, .init(expectedRevision: 3,
                change: .request(command: request.operation, value: request)))
            var saved = try await reopenedRequest(run)
            #expect(saved.startCommitted && !saved.hasReconciled && !saved.canRun)

            _ = try await transitionRequest(run, request, "remote-not-started",
                .reconciled(fixture.remote(request, observation: 1, result: .notExecuted)))
            #expect(try await reopenedRequest(run).canRun)
            let first = TransferAttemptID(rawValue: "request-attempt-first")
            _ = try await transitionRequest(run, request, "begin-first", .beginAttempt(first))
            _ = try await transitionRequest(run, request, "wait-wifi", .wait(.wiFiUnavailable, active: true))
            _ = try await transitionRequest(run, request, "wait-saving", .wait(.saving, active: true))
            _ = try await transitionRequest(run, request, "user-pause", .pause)
            saved = try await reopenedRequest(run)
            #expect(saved.intent == .paused)
            #expect(saved.waits == [.wiFiUnavailable, .saving])
            #expect(saved.transport == .stopRequested && saved.attempt == first)
            #expect(!saved.hasReconciled && !saved.canRun)

            _ = try await transitionRequest(run, request, "first-stop", .stopped(fixture.stop(request, first)))
            _ = try await transitionRequest(run, request, "wifi-returned", .wait(.wiFiUnavailable, active: false))
            saved = try await reopenedRequest(run)
            #expect(saved.intent == .paused && saved.waits == [.saving])
            #expect(saved.transport == .stopped && !saved.canRun)
            _ = try await transitionRequest(run, request, "user-resume", .resume)
            #expect(!(try await reopenedRequest(run)).canRun)
            _ = try await transitionRequest(run, request, "saving-ended", .wait(.saving, active: false))
            saved = try await reopenedRequest(run)
            #expect(saved.intent == .running && saved.waits.isEmpty)
            #expect(!saved.canRun, "A stopped attempt still requires a fresh remote observation")

            _ = try await transitionRequest(run, request, "remote-in-progress",
                .reconciled(fixture.remote(request, observation: 2, result: .inProgress)))
            #expect(try await reopenedRequest(run).canRun)
            let second = TransferAttemptID(rawValue: "request-attempt-second")
            _ = try await transitionRequest(run, request, "begin-second", .beginAttempt(second))
            for (command, value) in [
                ("late-first-stop", MediaRequestTransition.stopped(fixture.stop(request, first))),
                ("late-first-completion", .completed(fixture.completion(request, first)))
            ] {
                let mutation = try await requestTransitionMutation(run, request, command, value)
                try await requireRejectedUnchanged(run, mutation, .identityMismatch)
            }
            saved = try await reopenedRequest(run)
            #expect(saved.attempt == second && saved.transport == .active)
            _ = try await transitionRequest(run, request, "second-completion", .completed(fixture.completion(request, second)))
            saved = try await reopenedRequest(run)
            #expect(saved.transport == .completed && saved.remote == .inProgress)
            #expect(!saved.canRun)
            let lateStop = try await requestTransitionMutation(run, request, "stop-after-completion",
                                                               .stopped(fixture.stop(request, second)))
            try await requireRejectedUnchanged(run, lateStop, .wrongStage)
            let snapshot = try await reopenedRequestSnapshot(run)
            #expect(snapshot.verifications.isEmpty && snapshot.confirmations.isEmpty && snapshot.outbox.isEmpty)
        }
    }

    @Test func cancellationAndRemoteObservationOrderSurviveLateSuccessAndAnotherReopen() async throws {
        try await withStorageRun { run in
            let fixture = try RequestStoreFixture()
            try await prepareRequestStore(run, fixture: fixture)
            let request = fixture.request()
            _ = try await requireRequestCommit(run, .init(expectedRevision: 3,
                change: .request(command: request.operation, value: request)))
            _ = try await transitionRequest(run, request, "remote-before-cancel",
                .reconciled(fixture.remote(request, observation: 10, result: .notExecuted)))
            let attempt = TransferAttemptID(rawValue: "request-cancelled-attempt")
            _ = try await transitionRequest(run, request, "begin-cancelled-attempt", .beginAttempt(attempt))
            _ = try await transitionRequest(run, request, "cancel-request", .cancel)
            var saved = try await reopenedRequest(run)
            #expect(saved.intent == .cancelled && saved.transport == .stopRequested)

            let evidence = EvidenceID(rawValue: "synthetic-remote-success")
            _ = try await transitionRequest(run, request, "late-server-success",
                .reconciled(fixture.remote(request, observation: 11, result: .succeeded(evidence))))
            saved = try await reopenedRequest(run)
            #expect(saved.intent == .cancelled && saved.transport == .stopRequested)
            #expect(saved.remote == .succeeded(evidence) && !saved.canRun)
            _ = try await transitionRequest(run, request, "late-local-completion", .completed(fixture.completion(request, attempt)))
            saved = try await reopenedRequest(run)
            #expect(saved.intent == .cancelled && saved.transport == .completed)
            #expect(saved.remote == .succeeded(evidence) && saved.lastObservation == .init(rawValue: 11))
            let resume = try await requestTransitionMutation(run, request, "resume-cancelled", .resume)
            try await requireRejectedUnchanged(run, resume, .wrongStage)

            for generation: UInt64 in [10, 11] {
                let stale = try await requestTransitionMutation(run, request, "stale-remote-\(generation)",
                    .reconciled(fixture.remote(request, observation: generation, result: .notExecuted)))
                try await requireRejectedUnchanged(run, stale, .staleGeneration)
            }
            _ = try await transitionRequest(run, request, "later-query-unavailable",
                .reconciled(fixture.remote(request, observation: 12, result: .unknown)))
            saved = try await reopenedRequest(run)
            #expect(saved.lastObservation == .init(rawValue: 12))
            #expect(saved.remote == .succeeded(evidence), "A newer failed query cannot erase an observed success")
            #expect(saved.intent == .cancelled && !saved.canRun)
            let conflicting = try await requestTransitionMutation(run, request, "conflicting-success",
                .reconciled(fixture.remote(request, observation: 13,
                                           result: .succeeded(.init(rawValue: "different-evidence")))))
            try await requireRejectedUnchanged(run, conflicting, .identityMismatch)
            #expect(try await reopenedRequest(run) == saved)
        }
    }

    @Test func admissionAndExactCommandsRejectCallerStateWrongIdentityAndStaleGlobalRevision() async throws {
        try await withStorageRun { run in
            let fixture = try RequestStoreFixture()
            try await prepareRequestStore(run, fixture: fixture)
            let request = fixture.request()
            // Model an untrusted decoded payload attempting to write a private
            // committed flag. No fake commit receipt is used to start the test.
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
            object["startCommitted"] = true
            let forged = try JSONDecoder().decode(MediaRequest.self,
                from: JSONSerialization.data(withJSONObject: object))
            try #require(forged.startCommitted)
            try await requireRejectedUnchanged(run, .init(expectedRevision: 3,
                change: .request(command: forged.operation, value: forged)), .identityMismatch)
            let unregistered = fixture.request(registration: fixture.otherRegistration)
            try await requireRejectedUnchanged(run, .init(expectedRevision: 3,
                change: .request(command: unregistered.operation, value: unregistered)), .notCommitted)
            let unpublished = fixture.request(target: .rendition(fixture.otherRendition))
            try await requireRejectedUnchanged(run, .init(expectedRevision: 3,
                change: .request(command: unpublished.operation, value: unpublished)), .identityMismatch)

            let start = BackendStoreMutation(expectedRevision: 3, change: .request(command: request.operation, value: request))
            let startReceipt = try await requireRequestCommit(run, start)
            let started = try await reopenedRequestSnapshot(run)
            #expect(try await lookupRequestCommit(run, start) == .committed(startReceipt))
            #expect(try await commitRequestOnce(run, start) == .committed(startReceipt))
            #expect(try await reopenedRequestSnapshot(run) == started)

            var replacement = try await reopenedRequest(run)
            replacement.pause()
            let overwrite = BackendStoreMutation(expectedRevision: 3,
                change: .request(command: request.operation, value: replacement))
            #expect(try await commitRequestOnce(run, overwrite) == .rejected(.identityMismatch))
            #expect(try await lookupRequestCommit(run, overwrite) == .rejected(.identityMismatch))
            #expect(try await reopenedRequestSnapshot(run) == started)

            let pause = try await requestTransitionMutation(run, request, "exact-pause", .pause)
            let pauseReceipt = try await requireRequestCommit(run, pause)
            let paused = try await reopenedRequestSnapshot(run)
            #expect(try await lookupRequestCommit(run, pause) == .committed(pauseReceipt))
            #expect(try await commitRequestOnce(run, pause) == .committed(pauseReceipt))
            #expect(try await reopenedRequestSnapshot(run) == paused)
            let changedPayload = BackendStoreMutation(expectedRevision: pause.expectedRevision,
                change: .requestTransition(command: .init(rawValue: "exact-pause"), operation: request.operation,
                    target: request.target, registration: request.registration, value: .resume))
            #expect(try await commitRequestOnce(run, changedPayload) == .rejected(.identityMismatch))
            #expect(try await lookupRequestCommit(run, changedPayload) == .rejected(.identityMismatch))
            #expect(try await reopenedRequestSnapshot(run) == paused)

            let stale = BackendStoreMutation(expectedRevision: pause.expectedRevision,
                change: .requestTransition(command: .init(rawValue: "stale-global-cas"), operation: request.operation,
                    target: request.target, registration: request.registration, value: .resume))
            try await requireRejectedUnchanged(run, stale, .revisionConflict)
            let wrongTarget = MediaTarget.rendition(fixture.otherRendition)
            let wrongCommands: [BackendStoreChange] = [
                .requestTransition(command: .init(rawValue: "wrong-target"), operation: request.operation,
                    target: wrongTarget, registration: request.registration, value: .cancel),
                .requestTransition(command: .init(rawValue: "wrong-registration"), operation: request.operation,
                    target: request.target, registration: fixture.otherRegistration, value: .cancel),
                .requestTransition(command: .init(rawValue: "wrong-remote-target"), operation: request.operation,
                    target: request.target, registration: request.registration,
                    value: .reconciled(.init(context: .init(operation: request.operation, registration: request.registration,
                        target: wrongTarget, session: nil), observation: .init(rawValue: 1), result: .notExecuted))),
                .requestTransition(command: .init(rawValue: "wrong-remote-registration"), operation: request.operation,
                    target: request.target, registration: request.registration,
                    value: .reconciled(.init(context: .init(operation: request.operation, registration: fixture.otherRegistration,
                        target: request.target, session: nil), observation: .init(rawValue: 1), result: .notExecuted)))
            ]
            for change in wrongCommands {
                try await requireRejectedUnchanged(run, .init(expectedRevision: paused.revision, change: change), .identityMismatch)
            }
            #expect(try await reopenedRequestSnapshot(run) == paused)
        }
    }
}

/// Synthetic identities and authenticated-control-plane observations, not real
/// server/media evidence. All local commit receipts come from the SQLite writer.
nonisolated private struct RequestStoreFixture {
    let intent: RegistrationIntent
    let registration: RegistrationIdentity
    let otherRegistration: RegistrationIdentity
    let rendition: RenditionIdentity
    let otherRendition: RenditionIdentity

    init() throws {
        let destination = DestinationIdentity(rawValue: "request-store-destination")
        intent = .init(operation: .init(rawValue: "request-store-register"), destination: destination)
        registration = .init(destination: destination, id: .init(rawValue: "request-store-device"), generation: .init(rawValue: 1))
        otherRegistration = .init(destination: destination, id: .init(rawValue: "request-store-other-device"), generation: .init(rawValue: 2))
        let original = OriginalContent(capture: .init(rawValue: "request-store-remote-original"), generation: .init(rawValue: 1),
            content: try .init(byteCount: 4096, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
        rendition = try Self.makeRendition(original, name: "published", generation: 1, digest: "b")
        otherRendition = try Self.makeRendition(original, name: "not-published", generation: 2, digest: "c")
    }

    private static func makeRendition(_ original: OriginalContent, name: String,
                                     generation: UInt64, digest: String) throws -> RenditionIdentity {
        .init(original: original, inputLogIdentity: "synthetic-log", transformAssetIdentity: "synthetic-transform",
              transformAssetVersion: "synthetic-v1", outputConfigurationIdentity: "synthetic-output",
              conversionVersion: "synthetic-v1", rendition: .init(rawValue: "request-store-\(name)"),
              deliveryContent: try .init(byteCount: 512, algorithm: "sha256", digest: String(repeating: digest, count: 64)),
              publicationGeneration: .init(rawValue: generation))
    }

    func request(target: MediaTarget? = nil, registration: RegistrationIdentity? = nil) -> MediaRequest {
        .init(operation: .init(rawValue: "request-store-download"), target: target ?? .rendition(rendition),
              purpose: .download, registration: registration ?? self.registration, expectedStartRevision: 3)
    }

    func remote(_ request: MediaRequest, observation: UInt64, result: BackendOutcome<EvidenceID>) -> RemoteOperationResult {
        .init(context: .init(operation: request.operation, registration: request.registration, target: request.target, session: nil),
              observation: .init(rawValue: observation), result: result)
    }

    func stop(_ request: MediaRequest, _ attempt: TransferAttemptID) -> TransportStopReceipt {
        .init(operation: request.operation, attempt: attempt, target: request.target, registration: request.registration)
    }

    func completion(_ request: MediaRequest, _ attempt: TransferAttemptID) -> TransportCompletionReceipt {
        .init(operation: request.operation, attempt: attempt, target: request.target, registration: request.registration)
    }
}

nonisolated private func prepareRequestStore(_ run: ExplorationRunDirectory, fixture: RequestStoreFixture) async throws {
    let intent = try await requireRequestCommit(run, .init(expectedRevision: 0, change: .registrationIntent(fixture.intent)),
                                               mode: .createNew)
    let server = RegistrationServerReceipt(intent: fixture.intent, registration: fixture.registration)
    let registration = try await requireRequestCommit(run, .init(expectedRevision: 1, change: .registration(server)))
    let publication = PublishedRenditionObservation(command: .init(rawValue: "request-store-publication"),
        registration: fixture.registration, rendition: fixture.rendition, observation: .init(rawValue: 1),
        invalidationGeneration: .init(rawValue: 0))
    let published = try await requireRequestCommit(run, .init(expectedRevision: 2, change: .publication(publication)))
    let snapshot = try await reopenedRequestSnapshot(run)
    try #require(snapshot.revision == 3 && snapshot.requests.isEmpty)
    #expect(snapshot.registrationIntents == [.init(intent: fixture.intent, commit: intent)])
    #expect(snapshot.registrations == [.init(server: server, intentCommit: intent, commit: registration)])
    #expect(snapshot.publications == [.init(observation: publication, commit: published)])
    let store = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
    #expect(await store.loadRecordings() == .loaded(.init(revision: 3, recordings: [])))
    guard case .succeeded(let originals) = await store.loadOriginalState() else {
        Issue.record("Expected a persisted remote-only original"); throw BackendContractError.unavailable
    }
    #expect(originals.originals.isEmpty)
    #expect(originals.logicalOriginals.map(\.original) == [fixture.rendition.original])
    #expect(originals.logicalOriginals.allSatisfy { $0.binding == nil })
}

/// The adapter is local to each call. Every observation below reopens the disk
/// store, not a test-side MediaRequest or a still-retained in-memory projection.
nonisolated private func commitRequestOnce(_ run: ExplorationRunDirectory, _ mutation: BackendStoreMutation,
    mode: ExplorationStoreOpenMode = .openExisting) async throws -> BackendCommitResult {
    let store = try SQLiteRecordingStore(run: run, mode: mode)
    return await store.commit(mutation)
}

nonisolated private func requireRequestCommit(_ run: ExplorationRunDirectory, _ mutation: BackendStoreMutation,
    mode: ExplorationStoreOpenMode = .openExisting) async throws -> BackendCommitReceipt {
    let result = try await commitRequestOnce(run, mutation, mode: mode)
    guard case .committed(let receipt) = result else {
        Issue.record("Expected real SQLite commit for \(mutation.change.key), got \(result)")
        throw BackendContractError.notCommitted
    }
    try #require(receipt.matches(mutation.change.key, revision: mutation.expectedRevision))
    return receipt
}

nonisolated private func lookupRequestCommit(_ run: ExplorationRunDirectory,
                                             _ mutation: BackendStoreMutation) async throws -> BackendCommitResult {
    let store = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
    return await store.lookupCommit(mutation)
}

nonisolated private func reopenedRequestSnapshot(_ run: ExplorationRunDirectory) async throws -> BackendStoreSnapshot {
    let store = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
    guard case .loaded(let snapshot) = await store.load() else {
        Issue.record("Expected reopened media-operation snapshot"); throw BackendContractError.unavailable
    }
    return snapshot
}

nonisolated private func reopenedRequest(_ run: ExplorationRunDirectory) async throws -> MediaRequest {
    let snapshot = try await reopenedRequestSnapshot(run)
    try #require(snapshot.requests.count == 1)
    return try #require(snapshot.requests.first)
}

nonisolated private func requestTransitionMutation(_ run: ExplorationRunDirectory, _ request: MediaRequest,
    _ command: String, _ value: MediaRequestTransition) async throws -> BackendStoreMutation {
    let snapshot = try await reopenedRequestSnapshot(run)
    return .init(expectedRevision: snapshot.revision,
        change: .requestTransition(command: .init(rawValue: command), operation: request.operation,
            target: request.target, registration: request.registration, value: value))
}

@discardableResult nonisolated private func transitionRequest(_ run: ExplorationRunDirectory, _ request: MediaRequest,
    _ command: String, _ value: MediaRequestTransition) async throws -> BackendCommitReceipt {
    let mutation = try await requestTransitionMutation(run, request, command, value)
    return try await requireRequestCommit(run, mutation)
}

nonisolated private func requireRejectedUnchanged(_ run: ExplorationRunDirectory, _ mutation: BackendStoreMutation,
                                                 _ reason: BackendContractError) async throws {
    let before = try await reopenedRequestSnapshot(run)
    #expect(try await commitRequestOnce(run, mutation) == .rejected(reason))
    #expect(try await lookupRequestCommit(run, mutation) == .unknown)
    #expect(try await reopenedRequestSnapshot(run) == before)
}
