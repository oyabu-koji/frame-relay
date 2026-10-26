import Foundation
import Testing
@testable import FrameRelay

@MainActor struct LibraryTransferCommandsTests {
    @Test func firstSuspensionHasEveryChildAndSavedBindingAndLaterSelectionCannotReplaceThem() async throws {
        let f = try await UploadAppFixture.make(names: ["one", "two", "three"])
        let snapshot = try await uploadAppLibrary(f), reader = UploadAppMemoryReader(snapshot)
        let port = UploadAppAcceptanceProbe(), commands = LibraryTransferCommands(acceptance: port, network: UploadAppNetwork(.wiFi))
        let model = LibraryModel(reader: reader, transfers: commands)
        await model.refresh()
        let first = snapshot.items[0].id, second = snapshot.items[1].id, third = snapshot.items[2].id
        model.select(first, selected: true); model.select(second, selected: true)
        let submit = Task { await model.submit(.transfer, captures: model.selected) }
        await port.waitForCalls(accepts: 1)
        let fixed = try #require(model.pendingTransferAcceptance)
        #expect(fixed.targets.map(\.binding) == snapshot.items.prefix(2).compactMap(\.uploadCandidateBinding))
        #expect(fixed.storeIdentity == snapshot.storeIdentity && fixed.registration == snapshot.uploadRegistration)
        #expect(fixed.scope == .multiple && Set(fixed.targets.map(\.operation)).count == 2)
        #expect(!fixed.targets.contains { $0.operation == fixed.parent })
        // Removing a visible row during refresh does not silently shrink the
        // user's selected set or substitute the other original after suspension.
        let changed = LibrarySnapshot(revision: snapshot.revision + 1, items: [snapshot.items[0], snapshot.items[2]],
            storeIdentity: .init(rawValue: UUID()), uploadRegistration: snapshot.uploadRegistration)
        await reader.replace(changed); await model.refresh()
        #expect(model.selected == [first, second])
        model.select(second, selected: false); model.select(third, selected: true)
        await model.submit(.transfer, captures: model.selected)
        #expect(port.accepted == [fixed] && model.pendingTransferAcceptance == fixed)
        port.finish(.recorded(try uploadAppRecord(fixed)))
        await submit.value
        #expect(model.pendingTransferAcceptance == nil && model.submissions.isEmpty)
        #expect(model.transferMessage?.contains("通信はまだ開始していません") == true)
        #expect(port.lookedUp.isEmpty)
        try await f.assertUnchanged()
    }

    @Test func ownerKeepsUnknownInputAndEveryRepeatBecomesAnExactLookup() async throws {
        let f = try await UploadAppFixture.make(), request = try await f.request()
        let probe = UploadAppAcceptanceProbe(), commands = LibraryTransferCommands(acceptance: probe, network: UploadAppNetwork(.wiFi))
        let submit = Task { await commands.accept(request) }
        await probe.waitForCalls(accepts: 1)
        #expect(await commands.accept(request) == .unknown)
        probe.finish(.unknown); #expect(await submit.value == .unknown)
        let other = try await f.request()
        #expect(await commands.accept(other) == .rejected(.wrongStage))
        let same = Task { await commands.accept(request) }
        await probe.waitForCalls(accepts: 1, lookups: 1)
        #expect(OriginalUploadAcceptanceValueValidation.exact(probe.lookedUp[0], request))
        probe.finish(.recorded(try uploadAppRecord(other)))
        #expect(await same.value == .unknown)
        let lookup = Task { await commands.lookupAcceptance(request) }
        await probe.waitForCalls(accepts: 1, lookups: 2)
        let record = try uploadAppRecord(request)
        probe.finish(.recorded(record))
        #expect(await lookup.value == .recorded(record))
        #expect(probe.accepted.count == 1 && probe.lookedUp.count == 2)
    }

    @Test(arguments: ["missing-binding", "duplicate-binding", "missing-registration", "ambiguous-destinations"])
    func incompleteOrAliasedSelectionNeverSilentlyDropsAChild(fault: String) async throws {
        let f = try await UploadAppFixture.make(names: ["one", "two"])
        let original = try await uploadAppLibrary(f)
        var items = original.items
        if fault == "missing-binding" { items[1].uploadCandidateBinding = nil }
        if fault == "duplicate-binding" { items[1].uploadCandidateBinding = items[0].uploadCandidateBinding }
        var registration = original.uploadRegistration
        if fault == "missing-registration" { registration = nil }
        if fault == "ambiguous-destinations" {
            _ = try await mediaRegister(f.store, registration: .init(destination: .init(rawValue: "other-destination"),
                id: .init(rawValue: UUID().uuidString), generation: .init(rawValue: 1)))
            registration = OriginalUploadAcceptanceBoundary.currentRegistration(try await mediaSnapshot(f.store))
            #expect(registration == nil)
        }
        let snapshot = LibrarySnapshot(revision: original.revision, items: items,
            storeIdentity: original.storeIdentity, uploadRegistration: registration)
        let probe = UploadAppAcceptanceProbe(), commands = LibraryTransferCommands(acceptance: probe, network: UploadAppNetwork(.wiFi))
        let model = LibraryModel(reader: UploadAppMemoryReader(snapshot), transfers: commands)
        await model.refresh()
        let selected = Set(items.map(\.id))
        for id in selected { model.select(id, selected: true) }
        await model.submit(.transfer, captures: selected)
        #expect(probe.accepted.isEmpty && probe.lookedUp.isEmpty)
        #expect(model.pendingTransferAcceptance == nil && model.selected == selected)
        #expect(model.transferMessage != nil && model.submissions.isEmpty)
    }

    @Test func singleDetailAndRecordedGroupUseTypedRequestAndNeverManufactureAnOperationSuccess() async throws {
        let f = try await UploadAppFixture.make(), snapshot = try await uploadAppLibrary(f)
        let probe = UploadAppAcceptanceProbe(), commands = LibraryTransferCommands(acceptance: probe, network: UploadAppNetwork(.wiFi))
        let reader = UploadAppMemoryReader(snapshot), model = LibraryModel(reader: reader, transfers: commands)
        await model.refresh()
        #expect(LibraryAction.detail.contains(.transfer) && !LibraryAction.single.contains(.transfer))
        let submit = Task { await model.submit(.transfer, captures: [snapshot.items[0].id]) }
        await probe.waitForCalls(accepts: 1)
        let request = try #require(probe.accepted.first), record = try uploadAppRecord(request)
        #expect(request.scope == .single && request.targets.count == 1)
        probe.finish(.recorded(record)); await submit.value
        var current = try #require(record.children[0].initialRequest)
        current.pause(); current.setWait(.recording, active: true); current.setWait(.authentication, active: true)
        let row = LibraryMediaRequest(request: current)
        #expect(LibraryTransferProjection.currentRequest(record.children[0], record: record, rows: [row]) == row)
        #expect(row.intentDescription.contains("停止") && row.waitsDescription.contains("撮影中"))
        var latest = snapshot; latest.originalUploadAcceptances = [record]; latest.mediaRequests = [row]
        await reader.replace(latest)
        let reopenedProbe = UploadAppAcceptanceProbe()
        let reopened = LibraryModel(reader: reader,
            transfers: LibraryTransferCommands(acceptance: reopenedProbe, network: UploadAppNetwork(.offline)))
        await reopened.refresh()
        #expect(reopenedProbe.accepted.isEmpty && reopenedProbe.lookedUp.isEmpty)
        let lookup = Task { await reopened.lookupRecordedTransfer(record) }
        await reopenedProbe.waitForCalls(accepts: 0, lookups: 1)
        #expect(OriginalUploadAcceptanceValueValidation.exact(reopenedProbe.lookedUp[0], record.plan.request))
        reopenedProbe.finish(.recorded(record)); await lookup.value
        #expect(reopenedProbe.accepted.isEmpty && reopened.submissions.isEmpty)
        #expect(reopened.snapshot?.items[0].operationResults.isEmpty == true)
        #expect(reopened.snapshot?.mediaRequests[0].request.intent == .paused)
    }
}

actor UploadAppMemoryReader: LibraryReadPort {
    private var snapshot: LibrarySnapshot
    init(_ snapshot: LibrarySnapshot) { self.snapshot = snapshot }
    func loadLibrary() -> LibraryLoadResult { .loaded(snapshot) }
    func replace(_ snapshot: LibrarySnapshot) { self.snapshot = snapshot }
}

@MainActor final class UploadAppAcceptanceProbe: OriginalUploadAcceptancePort {
    private(set) var accepted: [OriginalUploadAcceptanceRequest] = []
    private(set) var lookedUp: [OriginalUploadAcceptanceRequest] = []
    private var response: CheckedContinuation<OriginalUploadAcceptanceResult, Never>?
    private var waiting: (Int, Int, CheckedContinuation<Void, Never>)?
    @MainActor func accept(_ request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult {
        accepted.append(request)
        return await withCheckedContinuation { response = $0; signal() }
    }
    @MainActor func lookupAcceptance(_ request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult {
        lookedUp.append(request)
        return await withCheckedContinuation { response = $0; signal() }
    }
    func waitForCalls(accepts: Int, lookups: Int = 0) async {
        if accepted.count >= accepts && lookedUp.count >= lookups { return }
        await withCheckedContinuation { waiting = (accepts, lookups, $0) }
    }
    private func signal() {
        guard let waiting, accepted.count >= waiting.0, lookedUp.count >= waiting.1 else { return }
        self.waiting = nil; waiting.2.resume()
    }
    func finish(_ result: OriginalUploadAcceptanceResult) {
        let held = response; response = nil; held?.resume(returning: result)
    }
}

nonisolated func uploadAppLibrary(_ fixture: UploadAppFixture) async throws -> LibrarySnapshot {
    guard case .loaded(let snapshot) = await LibraryStoreReader(store: fixture.store, files: fixture.files).loadLibrary() else {
        throw BackendContractError.unavailable
    }
    return snapshot
}

nonisolated func uploadAppRecord(_ request: OriginalUploadAcceptanceRequest) throws -> StoredOriginalUploadAcceptance {
    let plan = try OriginalUploadAcceptancePlan(request: request,
        presences: request.targets.map { .present(byteCount: $0.binding.original.content.byteCount) })
    let receipt = BackendCommitReceipt(key: .originalUploadAcceptance(request.parent), previousRevision: 40, committedRevision: 41)
    let children = try request.targets.enumerated().map { index, target in
        var initial = MediaRequest(operation: target.operation, target: .original(target.binding.original), purpose: .upload,
            registration: request.registration.server.registration, expectedStartRevision: receipt.previousRevision)
        try initial.acceptOriginalUploadAcceptanceCommit(receipt, plan: plan)
        return OriginalUploadAcceptanceChild(target: target, presence: plan.presences[index], decision: .accepted, initialRequest: initial)
    }
    return .init(plan: plan, children: children, commit: receipt, expectedStoreIdentity: request.storeIdentity)
}
