import Testing
@testable import FrameRelay

@MainActor struct LibraryModelTests {
    @Test func overlappingRefreshWaitsForANewReadInsteadOfLosingCommittedRows() async throws {
        let first = try librarySnapshot(["one"])
        let latest = LibrarySnapshot(revision: 4, items: try librarySnapshot(["one", "two"]).items)
        let firstGate = ProductCaptureTestGate()
        let nextGate = ProductCaptureTestGate()
        let reader = LibraryDelayedReader(initial: first, latest: latest, firstGate: firstGate, nextGate: nextGate)
        let model = LibraryModel(reader: reader)
        let firstRefresh = Task { await model.refresh() }
        await firstGate.waitUntilHeld()
        var refreshReturned = false
        var requestStarted = false
        let overlapping = Task {
            requestStarted = true
            await model.refresh()
            refreshReturned = true
        }
        while !requestStarted { await Task.yield() }
        #expect(!refreshReturned)
        await firstGate.release()
        await nextGate.waitUntilHeld()
        #expect(model.snapshot == first)
        #expect(model.isLoading)
        #expect(!refreshReturned)
        await nextGate.release()
        await firstRefresh.value
        await overlapping.value
        #expect(refreshReturned)
        #expect(model.snapshot == latest)
        #expect(!model.isLoading)
        #expect(await reader.reads == 2)
    }

    @Test func failedLoadKeepsPriorRowsAndNeverAppearsAsEmptySuccess() async throws {
        let initial = try librarySnapshot(["one"])
        let reader = LibraryMemoryReader(.loaded(initial))
        let model = LibraryModel(reader: reader)
        await model.refresh()
        await reader.replace(.unavailable(.corruptStore))
        await model.refresh()
        #expect(model.snapshot == initial)
        #expect(model.failure == .corruptStore)
        #expect(model.availability(.playOriginal, captures: [initial.items[0].id]) != .available)
        let newModel = LibraryModel(reader: reader)
        await newModel.refresh()
        #expect(newModel.snapshot == nil)
        #expect(newModel.failure == .corruptStore)
    }

    @Test func unconnectedActionsExplainWhyAndNeverCreateSuccess() async throws {
        let snapshot = try librarySnapshot(["one", "two"])
        let model = LibraryModel(reader: LibraryMemoryReader(.loaded(snapshot)))
        await model.refresh()
        for action in LibraryAction.allCases {
            let targets: Set<CaptureID> = action.supportsMultiple ? Set(snapshot.items.map(\.id)) : [snapshot.items[0].id]
            #expect(model.availability(action, captures: targets) == .unavailable(action.unavailableReason))
            await model.submit(action, captures: targets, discardRiskAcknowledged: true)
            #expect(model.submission == nil)
        }
        #expect(model.snapshot == snapshot)
        #expect(model.snapshot?.items.allSatisfy { $0.operationResults.isEmpty } == true)
    }

    @Test(arguments: LibraryAction.multiple)
    func fixedTargetsAndDoubleInputDoNotChangeSelectionIntoIntent(action: LibraryAction) async throws {
        let snapshot = try librarySnapshot(["one", "two", "three"])
        let reader = LibraryMemoryReader(.loaded(snapshot))
        let commands = LibrarySuspendedCommands()
        let model = LibraryModel(reader: reader, commands: commands)
        await model.refresh()
        let first = snapshot.items[0].id, second = snapshot.items[1].id, third = snapshot.items[2].id
        model.select(first, selected: true)
        model.select(second, selected: true)
        let task = Task { await model.submit(action, captures: model.selected) }
        await commands.waitForSubmission()
        model.select(second, selected: false)
        model.select(third, selected: true)
        await model.submit(action, captures: model.selected)
        #expect(await commands.requests.count == 1)
        #expect(Set(model.submission!.request.targets.map(\.capture)) == [first, second])
        #expect(model.selected == [first, third])
        await commands.finish(.accepted)
        await task.value
        #expect(model.submission?.phase == .awaitingRecordedResult)
        #expect(model.snapshot == snapshot)
        await model.submit(action, captures: [second])
        #expect(await commands.requests.count == 1)
    }

    @Test(arguments: LibraryAction.single)
    func singleActionsRejectMultipleTargets(action: LibraryAction) async throws {
        let snapshot = try librarySnapshot(["one", "two"])
        let commands = LibrarySuspendedCommands()
        let model = LibraryModel(reader: LibraryMemoryReader(.loaded(snapshot)), commands: commands)
        await model.refresh()
        await model.submit(action, captures: Set(snapshot.items.map(\.id)), discardRiskAcknowledged: true)
        #expect(await commands.requests.isEmpty)
        #expect(model.submission == nil)
        #expect(model.snapshot == snapshot)
    }

    @Test func discardRequiresTargetRiskAcknowledgementEvenWithAvailableHandler() async throws {
        let snapshot = try librarySnapshot(["one"])
        let commands = LibrarySuspendedCommands()
        let model = LibraryModel(reader: LibraryMemoryReader(.loaded(snapshot)), commands: commands)
        await model.refresh()
        await model.submit(.discard, captures: [snapshot.items[0].id])
        #expect(await commands.requests.isEmpty)
        #expect(model.inputIssue?.contains("消失リスク") == true)
        #expect(model.snapshot?.history.isEmpty == true)
    }

    @Test func perVideoResultsComeOnlyFromReadSnapshotAndSurviveModelRecreation() async throws {
        let initial = try librarySnapshot(["one", "two", "three", "four"])
        let reader = LibraryMemoryReader(.loaded(initial))
        let commands = LibrarySuspendedCommands()
        let model = LibraryModel(reader: reader, commands: commands)
        await model.refresh()
        let task = Task { await model.submit(.cleanup, captures: Set(initial.items.map(\.id))) }
        await commands.waitForSubmission()
        let request = try #require(model.submission?.request)
        let outcomes: [LibraryRecordedOutcome] = [.succeeded, .failed("合成失敗"), .notProcessed, .unknown]
        var items = initial.items
        for index in items.indices {
            items[index].operationResults = [.init(id: request.id, action: .cleanup, outcome: outcomes[index])]
        }
        let updated = LibrarySnapshot(revision: 9, items: items)
        await reader.replace(.loaded(updated))
        await commands.finish(.accepted)
        await task.value
        #expect(model.snapshot == updated)
        #expect(model.snapshot?.recordings.count == 4)
        #expect(model.snapshot?.history.isEmpty == true)
        #expect(model.availability(.cleanup, captures: [items[0].id]) == .available)
        #expect(model.availability(.cleanup, captures: [items[3].id]) != .available)
        let reopenedModel = LibraryModel(reader: reader)
        await reopenedModel.refresh()
        #expect(reopenedModel.snapshot?.items.map { $0.operationResults[0].outcome } == outcomes)
    }

    @Test func unknownAcceptanceBlocksRetryUntilRecordedResolution() async throws {
        let initial = try librarySnapshot(["one"])
        let reader = LibraryMemoryReader(.loaded(initial))
        let commands = LibrarySuspendedCommands()
        let model = LibraryModel(reader: reader, commands: commands)
        await model.refresh()
        let target = initial.items[0].id
        let task = Task { await model.submit(.saveToPhotos, captures: [target]) }
        await commands.waitForSubmission()
        await commands.finish(.unknown)
        await task.value
        #expect(model.submission?.phase == .reconciliationRequired)
        await model.submit(.saveToPhotos, captures: [target])
        #expect(await commands.requests.count == 1)
        var item = initial.items[0]
        item.operationResults = [.init(id: try #require(model.submission?.request.id), action: .saveToPhotos, outcome: .notProcessed)]
        await reader.replace(.loaded(.init(revision: 3, items: [item])))
        await model.refresh()
        #expect(model.availability(.saveToPhotos, captures: [target]) == .available)
    }

    @Test func unresolvedVideoDoesNotBlockAnotherVideoOrOriginalPlayback() async throws {
        let initial = try librarySnapshot(["one", "two"])
        let reader = LibraryMemoryReader(.loaded(initial))
        let commands = LibrarySuspendedCommands()
        let model = LibraryModel(reader: reader, commands: commands)
        await model.refresh()
        let first = initial.items[0].id, second = initial.items[1].id
        let task = Task { await model.submit(.saveToPhotos, captures: [first]) }
        await commands.waitForSubmission()
        await commands.finish(.unknown)
        await task.value
        #expect(model.availability(.saveToPhotos, captures: [first]) != .available)
        #expect(model.availability(.playOriginal, captures: [first]) == .available)
        #expect(model.availability(.saveToPhotos, captures: [second]) == .available)
        let otherTask = Task { await model.submit(.saveToPhotos, captures: [second]) }
        await commands.waitForSubmission(count: 2)
        await commands.finish(.accepted)
        await otherTask.value
        #expect(await commands.requests.count == 2)
        #expect(model.submissions.count == 2)
        #expect(model.submissions[0].phase == .reconciliationRequired)
        #expect(model.submissions[1].request.targets.map(\.capture) == [second])
        #expect(model.snapshot == initial)
    }

    @Test func playbackHandoffDoesNotWaitForAPersistentMediaOperationResult() async throws {
        let initial = try librarySnapshot(["one"])
        let commands = LibrarySuspendedCommands()
        let model = LibraryModel(reader: LibraryMemoryReader(.loaded(initial)), commands: commands)
        await model.refresh()
        let target = initial.items[0].id
        let task = Task { await model.submit(.playOriginal, captures: [target]) }
        await commands.waitForSubmission()
        #expect(model.availability(.playOriginal, captures: [target]) != .available)
        await commands.finish(.accepted)
        await task.value
        #expect(model.submission?.phase == .playbackHandedOff)
        #expect(model.availability(.playOriginal, captures: [target]) == .available)
        #expect(model.snapshot == initial)
    }
}

private actor LibraryDelayedReader {
    let initial: LibrarySnapshot
    let latest: LibrarySnapshot
    let firstGate: ProductCaptureTestGate
    let nextGate: ProductCaptureTestGate
    private(set) var reads = 0

    init(initial: LibrarySnapshot, latest: LibrarySnapshot,
         firstGate: ProductCaptureTestGate, nextGate: ProductCaptureTestGate) {
        self.initial = initial; self.latest = latest
        self.firstGate = firstGate; self.nextGate = nextGate
    }

    func loadLibrary() async -> LibraryLoadResult {
        reads += 1
        if reads == 1 {
            await firstGate.holdOnce()
            return .loaded(initial)
        }
        await nextGate.holdOnce()
        return .loaded(latest)
    }
}

extension LibraryDelayedReader: LibraryReadPort {}

private actor LibraryMemoryReader: LibraryReadPort {
    private var result: LibraryLoadResult
    init(_ result: LibraryLoadResult) { self.result = result }
    func loadLibrary() -> LibraryLoadResult { result }
    func replace(_ result: LibraryLoadResult) { self.result = result }
}

private actor LibrarySuspendedCommands: LibraryCommandPort {
    private(set) var requests: [LibraryCommandRequest] = []
    private var started: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<LibraryCommandResponse, Never>?

    nonisolated func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability { .available }
    func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse {
        requests.append(request)
        return await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
    }
    func waitForSubmission(count: Int = 1) async {
        if requests.count >= count { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ result: LibraryCommandResponse) {
        response?.resume(returning: result)
        response = nil
    }
}
