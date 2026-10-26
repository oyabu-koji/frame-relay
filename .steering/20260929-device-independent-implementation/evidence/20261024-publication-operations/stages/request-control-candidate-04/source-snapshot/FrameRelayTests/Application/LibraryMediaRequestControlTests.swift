import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct LibraryMediaRequestControlTests {
    @Test func unknownSingleRetainsEveryIDAndUsesOnlyExplicitLookupAfterRefresh() async throws {
        let request = try libraryControlRequest("single")
        let initial = libraryControlSnapshot([request])
        let reader = LibraryControlMemoryReader(initial), controls = LibraryControlProbe()
        let model = LibraryModel(reader: reader, requestControls: LibraryMediaRequestCommands(controls: controls))
        await model.refresh()
        let row = try #require(model.snapshot?.mediaRequests.first)
        let submit = Task { await model.controlMediaRequest(.pause, request: row) }
        await controls.waitForCalls(submits: 1)
        let plan = try #require(controls.submitted.first)
        #expect(model.pendingMediaControlPlan == plan && model.isSubmittingMediaControl)
        await model.controlMediaRequest(.cancel, request: row)
        #expect(controls.submitted.count == 1)
        controls.finish(.unknown); await submit.value
        var changed = libraryControlSnapshot([request, try libraryControlRequest("later")])
        changed.storeIdentity = initial.storeIdentity
        await reader.replace(changed); await model.refresh()
        #expect(model.pendingMediaControlPlan == plan && controls.lookedUp.isEmpty)
        #expect(model.allMediaPauseAvailability != .available)
        let lookup = Task { await model.reconcileMediaControl() }
        await controls.waitForCalls(submits: 1, lookups: 1)
        #expect(MediaPersonControlValueValidation.exact(controls.lookedUp[0], plan))
        #expect(controls.lookedUp[0].children.count == 1 && controls.lookedUp[0].children[0].target.matches(request))
        let record = libraryControlRecord(plan)
        controls.finish(.recorded(record, stops: [.init(child: plan.children[0].command, disposition: .requested)]))
        await lookup.value
        #expect(model.pendingMediaControlPlan == nil && !model.isSubmittingMediaControl)
        #expect(controls.submitted.count == 1 && controls.lookedUp.count == 1)
        #expect(model.mediaControlStops[plan.children[0].command] == .requested)
    }

    @Test func allPauseFixesQueuedWaitingAndTerminalRequestsBeforeTheFirstSuspension() async throws {
        var waiting = try libraryControlRequest("waiting")
        waiting.setWait(.recording, active: true); waiting.setWait(.wiFiUnavailable, active: true)
        var cancelled = try libraryControlRequest("cancelled"); cancelled.cancel()
        var completed = try libraryControlRequest("completed")
        try completed.reconcile(.init(context: .init(operation: completed.operation, registration: completed.registration,
            target: completed.target, session: nil), observation: .init(rawValue: 1), result: .notExecuted))
        let attempt = TransferAttemptID(rawValue: "completed-attempt")
        try completed.beginAttempt(attempt)
        try completed.observeCompletion(.init(operation: completed.operation, attempt: attempt,
            target: completed.target, registration: completed.registration))
        let requests = [try libraryControlRequest("queued"), waiting, cancelled, completed]
        let initial = libraryControlSnapshot(requests), reader = LibraryControlMemoryReader(initial)
        let controls = LibraryControlProbe(), model = LibraryModel(reader: reader, requestControls: controls)
        await model.refresh()
        let submit = Task { await model.pauseAllMediaRequests() }
        await controls.waitForCalls(submits: 1)
        let fixed = try #require(model.pendingMediaControlPlan)
        #expect(fixed.scope == .allPause && fixed.action == .pause && fixed.children.count == requests.count)
        #expect(zip(fixed.children, requests).allSatisfy { $0.target.matches($1) })
        #expect(Set(fixed.children.map(\.command)).count == requests.count)
        var later = libraryControlSnapshot(requests + [try libraryControlRequest("post-click")])
        later.storeIdentity = initial.storeIdentity
        await reader.replace(later); await model.refresh(); await model.pauseAllMediaRequests()
        #expect(model.pendingMediaControlPlan == fixed && controls.submitted.count == 1)
        #expect(!fixed.children.contains { $0.target.operation.rawValue == "post-click" })
        controls.finish(.unknown); await submit.value
        #expect(waiting.intent == .running && waiting.waits == [.recording, .wiFiUnavailable])
        #expect(cancelled.intent == .cancelled && completed.transport == .completed)
    }

    @Test func appOwnerKeepsUnknownPlanAndRejectsReplacementOrMismatchedConfirmation() async throws {
        let target = MediaPersonControlTarget(try libraryControlRequest("owner"))
        let plan = try libraryControlPlan([target])
        let controls = LibraryControlProbe(), owner = LibraryMediaRequestCommands(controls: controls)
        let submit = Task { await owner.submitPersonControl(plan) }
        await controls.waitForCalls(submits: 1)
        #expect(await owner.submitPersonControl(plan) == .unknown)
        controls.finish(.unknown); #expect(await submit.value == .unknown)
        let replacement = try libraryControlPlan([target])
        #expect(await owner.submitPersonControl(replacement) == .rejected(.wrongStage))
        let wrongRecord = Task { await owner.lookupPersonControl(plan) }
        await controls.waitForCalls(submits: 1, lookups: 1)
        controls.finish(.recorded(libraryControlRecord(replacement), stops: []))
        #expect(await wrongRecord.value == .unknown)
        // Even a submit of the same plan becomes a lookup after uncertainty.
        let same = Task { await owner.submitPersonControl(plan) }
        await controls.waitForCalls(submits: 1, lookups: 2)
        #expect(MediaPersonControlValueValidation.exact(controls.lookedUp[1], plan))
        let foreign = MediaPersonControlStopResult(child: .init(rawValue: "foreign-child"), disposition: .requested)
        controls.finish(.recorded(libraryControlRecord(plan), stops: [foreign]))
        #expect(await same.value == .unknown && controls.submitted.count == 1)
    }

    @Test func resumeIntentIsSeparateFromWaitsAndEndedCancelledCompletedRequestsStayDisabled() async throws {
        var paused = try libraryControlRequest("paused")
        paused.pause(); paused.setWait(.saving, active: true); paused.setWait(.authentication, active: true)
        let snapshot = libraryControlSnapshot([paused]), controls = LibraryControlProbe()
        let model = LibraryModel(reader: LibraryControlMemoryReader(snapshot), requestControls: controls)
        await model.refresh()
        let row = try #require(model.snapshot?.mediaRequests.first)
        #expect(model.mediaRequestAvailability(.resumeIntent, request: row) == .available)
        #expect(row.intentDescription.contains("停止") && row.waitsDescription.contains("保存中")
            && row.waitsDescription.contains("認証"))
        let resume = Task { await model.controlMediaRequest(.resumeIntent, request: row) }
        await controls.waitForCalls(submits: 1)
        let plan = try #require(controls.submitted.first)
        #expect(plan.action == .resumeIntent && plan.children[0].target.matches(paused))
        controls.finish(.recorded(libraryControlRecord(plan), stops: [.init(child: plan.children[0].command, disposition: .notRequired)]))
        await resume.value
        #expect(model.mediaControlMessage?.contains("実際の再開は行っていません") == true)
        #expect(model.snapshot?.mediaRequests[0].request == paused)
        var cancelled = paused; cancelled.cancel()
        var ended = try libraryControlRequest("ended", purpose: .playback); ended.pause(); try ended.endPlayback()
        for unavailable in [LibraryMediaRequest(request: cancelled), LibraryMediaRequest(request: ended)] {
            for action in [MediaPersonControlAction.pause, .cancel, .resumeIntent] {
                #expect(unavailable.availability(action) != .available)
            }
        }
        #expect(controls.submitted.count == 1 && controls.lookedUp.isEmpty)
    }

    @Test func operationProjectionUsesExactOriginalAndDestinationInsteadOfCaptureOrUnicodeAliases() throws {
        let original = try libraryControlOriginal("caf\u{00e9}")
        let alias = OriginalContent(capture: .init(rawValue: "cafe\u{0301}"), generation: original.generation, content: original.content)
        let destination = libraryControlRegistration().destination
        let other = RegistrationIdentity(destination: .init(rawValue: "other-destination"),
            id: .init(rawValue: "other-registration"), generation: .init(rawValue: 1))
        let one = try libraryControlRequest("one", original: original)
        let two = try libraryControlRequest("two", original: original, registration: other)
        let three = try libraryControlRequest("three", original: alias)
        let rows = [one, two, three].map { LibraryMediaRequest(request: $0) }
        #expect(LibraryMediaRequestProjection.matching(rows, original: original).map(\.id) == [one.operation, two.operation])
        #expect(LibraryMediaRequestProjection.matching(rows, original: original, destination: destination).map(\.id) == [one.operation])
        #expect(LibraryMediaRequestProjection.matching(rows, original: alias).map(\.id) == [three.operation])
        #expect(!LibraryMediaRequestProjection.samePresentation(one, try libraryControlRequest("one", original: alias)))
        let base = LibraryRemoteItem(destination: destination, original: original, hasIdentityConflict: false)
        var changed = base; changed.mediaRequests = [rows[0]]
        #expect(base != changed)
        #expect(LibraryMediaRequestProjection.stop(.requested).contains("通信処理の終了・媒体の使用解放は未確認"))
        #expect(LibraryMediaRequestProjection.stop(.notRequested).contains("自動で要求を繰り返しません"))
        #expect(rows[0].identityDescription == "対象：動画 caf\u{00e9}・原本")
        #expect(!rows[0].identityDescription.contains(one.operation.rawValue)
            && !rows[0].identityDescription.contains(one.registration.id.rawValue))
    }

    @Test func waitSetOrderDoesNotMakeTheSamePresentationStaleAndOtherStateRemainsExact() async throws {
        let waits: [MediaWaitReason] = [.wiFiUnavailable, .recording, .saving, .authentication]
        func presentation(_ order: [MediaWaitReason], session: String = "session-caf\u{00e9}",
            result: BackendOutcome<EvidenceID> = .inProgress) throws -> MediaRequest {
            var request = try libraryControlRequest("wait-set-order")
            for reason in order { request.setWait(reason, active: true) }
            try request.reconcile(.init(context: .init(operation: request.operation, registration: request.registration,
                target: request.target, session: .init(rawValue: session)), observation: .init(rawValue: 1), result: result))
            return request
        }
        let current = try presentation(waits), reversed = try presentation(Array(waits.reversed()))
        #expect(current.waits == reversed.waits && LibraryMediaRequestProjection.samePresentation(current, reversed))
        let controls = LibraryControlProbe()
        let model = LibraryModel(reader: LibraryControlMemoryReader(libraryControlSnapshot([current])), requestControls: controls)
        await model.refresh()
        #expect(model.mediaRequestAvailability(.pause, request: .init(request: reversed)) == .available)
        var differentWait = reversed; differentWait.setWait(.serverUnavailable, active: true)
        var differentIntent = reversed; differentIntent.pause()
        let aliasSession = try presentation(waits, session: "session-cafe\u{0301}")
        let differentRemote = try presentation(waits, result: .failed(.connectionUnavailable))
        for different in [differentWait, differentIntent, aliasSession, differentRemote] {
            #expect(!LibraryMediaRequestProjection.samePresentation(current, different))
            #expect(model.mediaRequestAvailability(.cancel, request: .init(request: different)) != .available)
        }
        #expect(controls.submitted.isEmpty && controls.lookedUp.isEmpty)
    }

    @Test(arguments: ["missing", "duplicate", "foreign"])
    func wholePlanStopResultsRequireEveryChildExactlyOnce(invalid: String) async throws {
        let targets = try [libraryControlRequest("coverage-one"), libraryControlRequest("coverage-two")].map {
            MediaPersonControlTarget($0)
        }
        let plan = try libraryControlPlan(targets), record = libraryControlRecord(plan)
        let first = MediaPersonControlStopResult(child: plan.children[0].command, disposition: .requested)
        let second = MediaPersonControlStopResult(child: plan.children[1].command, disposition: .notRequired)
        let malformed: [MediaPersonControlStopResult]
        switch invalid {
        case "missing": malformed = [first]
        case "duplicate": malformed = [first, first]
        default: malformed = [first, .init(child: .init(rawValue: "foreign-stop-child"), disposition: .unknown)]
        }
        #expect(!LibraryMediaRequestProjection.matches(record, stops: malformed, plan: plan))
        #expect(LibraryMediaRequestProjection.matches(record, stops: [second, first], plan: plan))
        let controls = LibraryControlProbe(), owner = LibraryMediaRequestCommands(controls: controls)
        let submit = Task { await owner.submitPersonControl(plan) }
        await controls.waitForCalls(submits: 1)
        controls.finish(.recorded(record, stops: malformed))
        #expect(await submit.value == .unknown)
        let lookup = Task { await owner.lookupPersonControl(plan) }
        await controls.waitForCalls(submits: 1, lookups: 1)
        #expect(MediaPersonControlValueValidation.exact(controls.lookedUp[0], plan))
        controls.finish(.recorded(record, stops: [second, first]))
        #expect(await lookup.value == .recorded(record, stops: [second, first]))
        #expect(controls.submitted.count == 1 && controls.lookedUp.count == 1)
    }

    @Test func staleRowsAndStoreWithoutIdentityCannotCreateAPlan() async throws {
        let request = try libraryControlRequest("stale"), controls = LibraryControlProbe()
        var snapshot = libraryControlSnapshot([request]); snapshot.storeIdentity = nil
        let reader = LibraryControlMemoryReader(snapshot), model = LibraryModel(reader: reader, requestControls: controls)
        await model.refresh()
        await model.controlMediaRequest(.pause, request: .init(request: request)); await model.pauseAllMediaRequests()
        #expect(controls.submitted.isEmpty && model.pendingMediaControlPlan == nil)
        await reader.replace(libraryControlSnapshot([request])); await model.refresh()
        var stale = request; stale.pause()
        #expect(model.mediaRequestAvailability(.cancel, request: .init(request: stale)) != .available)
        await model.controlMediaRequest(.cancel, request: .init(request: stale))
        #expect(controls.submitted.isEmpty)
    }

    @Test func sameWriterReaderProjectsEveryOperationAndReopenedHistoryNeverDispatches() async throws {
        try await withStorageRun { run in
            let f = try await ManifestSynchronizationFixture.make(run: run, names: ["control-local", "control-remote"])
            _ = try await statusKnownOriginal(f.originals[0], store: f.store)
            let renditions = f.originals.map { statusRendition($0) }
            for rendition in renditions {
                _ = try await mediaCommit(f.store, .publication(mediaPublication(rendition, registration: f.registration.server.registration)))
            }
            for index in 0..<3 {
                let before = try await mediaSnapshot(f.store)
                let request = MediaRequest(operation: .init(rawValue: "reader-control-\(index)"),
                    target: .rendition(renditions[index == 0 ? 0 : 1]), purpose: index == 2 ? .playback : .download,
                    registration: f.registration.server.registration, expectedStartRevision: before.revision)
                _ = try await mediaCommit(f.store, .request(command: request.operation, value: request))
            }
            let before = try await mediaSnapshot(f.store)
            let plan = try MediaPersonControlPlan(parent: .init(rawValue: "reader-control-parent"), storeIdentity: f.identity,
                scope: .allPause, action: .pause, children: before.requests.enumerated().map {
                    .init(command: .init(rawValue: "reader-control-child-\($0.offset)"), target: .init($0.element))
                })
            guard case .committed = await f.store.commit(.init(expectedRevision: before.revision,
                change: .personControl(plan), expectedStoreIdentity: f.identity)) else { throw BackendContractError.notCommitted }
            let reopened = try statusSynchronizationDisk(.sqlite, run: run, mode: .openExisting)
            let reader = LibraryStoreReader(store: reopened, files: StatusSynchronizationAbsentFiles())
            guard case .loaded(let snapshot) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
            #expect(snapshot.storeIdentity == f.identity && snapshot.mediaRequests.count == 3)
            #expect(snapshot.items.count == 1 && snapshot.items[0].mediaRequests.map(\.id) == [.init(rawValue: "reader-control-0")])
            #expect(snapshot.remoteItems.count == 1 && snapshot.remoteItems[0].mediaRequests.map(\.id)
                == [.init(rawValue: "reader-control-1"), .init(rawValue: "reader-control-2")])
            #expect(snapshot.personControls.count == 1 && snapshot.personControls[0].plan == plan)
            #expect(snapshot.mediaRequests.allSatisfy { $0.request.intent == .paused })
            let controls = LibraryControlProbe(), model = LibraryModel(reader: reader, requestControls: controls)
            await model.refresh(); await model.reconcileMediaControl(); await model.refresh()
            #expect(model.pendingMediaControlPlan == nil && model.mediaControlStops.isEmpty)
            #expect(controls.submitted.isEmpty && controls.lookedUp.isEmpty)
            let actual = try await mediaSnapshot(reopened)
            #expect(actual.personControls == snapshot.personControls && actual.backgroundTasks.isEmpty
                && actual.photoRegistrations.isEmpty && actual.temporaryMedia.isEmpty)
        }
    }
}

private actor LibraryControlMemoryReader: LibraryReadPort {
    private var snapshot: LibrarySnapshot
    init(_ snapshot: LibrarySnapshot) { self.snapshot = snapshot }
    func loadLibrary() -> LibraryLoadResult { .loaded(snapshot) }
    func replace(_ snapshot: LibrarySnapshot) { self.snapshot = snapshot }
}

@MainActor private final class LibraryControlProbe: MediaRequestControlPort {
    private(set) var submitted: [MediaPersonControlPlan] = []
    private(set) var lookedUp: [MediaPersonControlPlan] = []
    private var response: CheckedContinuation<MediaPersonControlResult, Never>?
    private var waiting: (Int, Int, CheckedContinuation<Void, Never>)?
    @MainActor func submitPersonControl(_ plan: MediaPersonControlPlan) async -> MediaPersonControlResult {
        submitted.append(plan)
        return await withCheckedContinuation { response = $0; signal() }
    }
    @MainActor func lookupPersonControl(_ plan: MediaPersonControlPlan) async -> MediaPersonControlResult {
        lookedUp.append(plan)
        return await withCheckedContinuation { response = $0; signal() }
    }
    func waitForCalls(submits: Int, lookups: Int = 0) async {
        if submitted.count >= submits && lookedUp.count >= lookups { return }
        await withCheckedContinuation { waiting = (submits, lookups, $0) }
    }
    private func signal() {
        guard let waiting, submitted.count >= waiting.0, lookedUp.count >= waiting.1 else { return }
        self.waiting = nil; waiting.2.resume()
    }
    func finish(_ result: MediaPersonControlResult) { let held = response; response = nil; held?.resume(returning: result) }
}

nonisolated private func libraryControlOriginal(_ capture: String = "control-original") throws -> OriginalContent {
    .init(capture: .init(rawValue: capture), generation: .init(rawValue: 1),
        content: try .init(byteCount: 4096, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
}
nonisolated private func libraryControlRegistration() -> RegistrationIdentity {
    .init(destination: .init(rawValue: "control-destination"), id: .init(rawValue: "control-registration"), generation: .init(rawValue: 1))
}
nonisolated private func libraryControlRequest(_ name: String, original: OriginalContent? = nil,
    purpose: MediaPurpose = .upload, registration: RegistrationIdentity? = nil) throws -> MediaRequest {
    let original = try original ?? libraryControlOriginal()
    var request = MediaRequest(operation: .init(rawValue: name),
        target: purpose == .upload ? .original(original) : .rendition(statusRendition(original)), purpose: purpose,
        registration: registration ?? libraryControlRegistration(), expectedStartRevision: 1)
    try request.acceptStartCommit(.init(key: .request(request.operation, request.target, request.registration),
        previousRevision: 1, committedRevision: 2))
    return request
}
nonisolated private func libraryControlSnapshot(_ requests: [MediaRequest]) -> LibrarySnapshot {
    .init(revision: 10, items: [], storeIdentity: .init(rawValue: UUID()), mediaRequests: requests.map { .init(request: $0) })
}
nonisolated private func libraryControlPlan(_ targets: [MediaPersonControlTarget]) throws -> MediaPersonControlPlan {
    try .init(parent: .init(rawValue: UUID().uuidString), storeIdentity: .init(rawValue: UUID()),
        scope: targets.count == 1 ? .single : .allPause, action: .pause,
        children: targets.map { .init(command: .init(rawValue: UUID().uuidString), target: $0) })
}
nonisolated private func libraryControlRecord(_ plan: MediaPersonControlPlan) -> StoredMediaPersonControlPlan {
    .init(plan: plan, commit: .init(key: .personControl(plan.parent), previousRevision: 10, committedRevision: 11),
        children: plan.children.map { .init(child: $0, decision: .recorded) })
}
