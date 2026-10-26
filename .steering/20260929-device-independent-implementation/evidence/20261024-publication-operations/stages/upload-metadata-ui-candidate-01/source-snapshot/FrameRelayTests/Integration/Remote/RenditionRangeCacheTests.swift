import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct RenditionRangeCacheTests {
    @Test func expandedRequestIsAuthorizedWhileExactSlicesAndCacheHitsKeepCurrentGate() async throws {
        try await withStorageRun { run in
            let bytes = cacheFixtureBytes()
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let client = ControlledRenditionHTTP(bytes: bytes)
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: client, scope: fixture.scope)
            #expect(try await reader.read(offset: 17, length: 37) == bytes.subdata(in: 17..<54))
            #expect(client.commands.first?.range == (try MediaByteRange(lowerBound: 17, upperBound: 65_553)))
            #expect(await gate.authorizations == 1)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.count == 1)
            await gate.setDenied(true)
            await #expect(throws: BackendContractError.notOnWiFi) { try await reader.read(offset: 54, length: 37) }
            #expect(client.commands.count == 1)
            await gate.setDenied(false)
            #expect(try await reader.read(offset: 54, length: 37) == bytes.subdata(in: 54..<91))
            let cached = await reader.diagnostics()
            #expect(client.commands.count == 1 && cached.cacheHits == 1)
            async let left = reader.read(offset: 100, length: 17)
            async let right = reader.read(offset: 200, length: 19)
            let parallel = try await (left, right)
            #expect(parallel.0 == bytes.subdata(in: 100..<117) && parallel.1 == bytes.subdata(in: 200..<219))
            #expect(client.commands.count == 1)
            #expect(try await reader.read(offset: 65_550, length: 37) == bytes.subdata(in: 65_550..<65_587))
            let authorizations = await gate.authorizations
            #expect(client.commands.count == 2 && authorizations == 2)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.count == 1)
            let before = await reader.diagnostics()
            #expect(before.cachePayloadBytes == 65_536 && before.peakCachePayloadBytes == 65_536)
            let terminal = try await fixture.scope.close()
            #expect(terminal.observations.count == terminal.registeredOwners)
            let after = await reader.diagnostics()
            #expect(after.cachePayloadBytes == 0 && after.bufferedResultPayloadBytes == 0 && after.activeReads == 0)
            #expect(client.invalidated && client.started == client.completed)
            await #expect(throws: BackendContractError.wrongStage) { try await reader.read(offset: 65_550, length: 1) }
        }
    }

    @Test(arguments: CacheInvalidation.allCases)
    func cachedBytesRejectChangedRegistrationInvalidationOrRealWriterEpoch(change: CacheInvalidation) async throws {
        try await withStorageRun { run in
            let bytes = cacheFixtureBytes()
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes), faultable: true)
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let client = ControlledRenditionHTTP(bytes: bytes)
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: client, scope: fixture.scope)
            _ = try await reader.read(offset: 0, length: 8)
            switch change {
            case .invalidation:
                let record = InvalidationRecord(id: .init(rawValue: "cache-invalidation"),
                    rendition: fixture.command.distribution.rendition, registration: fixture.command.distribution.registration,
                    generation: .init(rawValue: 1))
                _ = try await mediaOriginalCommit(fixture.store, .reserveInvalidation(.init(record)))
            case .registration:
                let prior = fixture.command.distribution.registration
                _ = try await mediaRegister(fixture.store, registration: .init(destination: prior.destination,
                    id: .init(rawValue: "cache-next-registration"), generation: .init(rawValue: 2)))
            case .epoch:
                let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
                fixture.faults?.replaceWriter(reopened)
            }
            await #expect(throws: BackendContractError.staleGeneration) { try await reader.read(offset: 8, length: 8) }
            #expect(client.commands.count == 1)
            if change == .epoch {
                await #expect(throws: BackendContractError.staleGeneration) { try await reader.close() }
                #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.count == 1)
            } else { _ = try await fixture.scope.close() }
            #expect((await reader.diagnostics()).cachePayloadBytes == 0)
        }
    }

    @Test func cancellingQueuedReadDoesNotCancelTheOtherConsumerOrDuplicateItsGET() async throws {
        try await withStorageRun { run in
            let bytes = cacheFixtureBytes()
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let client = ControlledRenditionHTTP(bytes: bytes); client.holdCallbacks = true
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: client, scope: fixture.scope)
            let first = Task { try await reader.read(offset: 0, length: 16) }
            #expect(await renditionEventually { client.started == 1 })
            let second = Task { try await reader.read(offset: 16, length: 16) }
            #expect(await renditionEventually { (await reader.diagnostics()).requestedReads == 2 })
            second.cancel()
            #expect(client.cancellationRequests == 0 && client.completed == 0)
            client.completePendingCallbacks()
            #expect(try await first.value == bytes.prefix(16))
            if case .success = await second.result { Issue.record("Cancelled queued read delivered bytes") }
            #expect(try await reader.read(offset: 16, length: 16) == bytes.subdata(in: 16..<32))
            #expect(client.started == 1)
            _ = try await fixture.scope.close()
        }
    }

    @Test func closeWaitsForActualCallbackAndCannotRestoreCacheFromLateCompletion() async throws {
        try await withStorageRun { run in
            let bytes = cacheFixtureBytes()
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let client = ControlledRenditionHTTP(bytes: bytes); client.holdCallbacks = true
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: client, scope: fixture.scope)
            let read = Task { try await reader.read(offset: 0, length: 16) }
            #expect(await renditionEventually { client.started == 1 })
            read.cancel()
            #expect(await renditionEventually { client.cancellationRequests == 1 })
            var closeReturned = false
            let closing = Task { let result = try await reader.close(); closeReturned = true; return result }
            #expect(await renditionEventually { client.closeRequested })
            #expect(!closeReturned && client.completed == 0 && !client.invalidated)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.count == 1)
            client.completePendingCallbacks()
            if case .success = await read.result { Issue.record("Cancelled response delivered bytes") }
            let terminal = try await closing.value
            #expect(terminal.started == 1 && terminal.completed == 1 && terminal.handlesClosed)
            let buffers = await reader.diagnostics()
            #expect(buffers.cachePayloadBytes == 0 && buffers.pendingResponsePayloadBytes == 0 && buffers.bufferedResultPayloadBytes == 0)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
            _ = try await fixture.scope.close()
        }
    }
}

nonisolated enum CacheInvalidation: String, CaseIterable, Sendable { case invalidation, registration, epoch }
nonisolated private func cacheFixtureBytes() -> Data { Data((0..<196_608).map { UInt8($0 % 251) }) }

/// Explicit lower-I/O fixture. Cancellation is a request; only
/// completePendingCallbacks observes terminal and resumes waiting readers.
@MainActor private final class ControlledRenditionHTTP: FixedRenditionHTTPTransport {
    private let bytes: Data
    var holdCallbacks = false
    private(set) var commands: [RetrieveMediaCommand] = []
    private(set) var started = 0
    private(set) var completed = 0
    private(set) var cancellationRequests = 0
    private(set) var closeRequested = false
    private(set) var invalidated = false
    private var received: UInt64 = 0
    private var pending: [UUID: (RetrieveMediaCommand, CheckedContinuation<Data, Error>)] = [:]
    private var cancelled: Set<UUID> = []
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    init(bytes: Data) { self.bytes = bytes }
    @MainActor func read(_ command: RetrieveMediaCommand) async throws -> Data {
        guard !closeRequested else { throw CancellationError() }
        commands.append(command); started += 1
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = (command, continuation)
                if !holdCallbacks { completePendingCallbacks() }
            }
        } onCancel: { Task { @MainActor in self.requestCancellation(id) } }
    }
    private func requestCancellation(_ id: UUID) {
        guard pending[id] != nil else { return }
        if cancelled.insert(id).inserted { cancellationRequests += 1 }
        if !holdCallbacks { completePendingCallbacks() }
    }
    func completePendingCallbacks() {
        let callbacks = pending; pending.removeAll()
        for (id, value) in callbacks {
            completed += 1
            if cancelled.remove(id) != nil { value.1.resume(throwing: CancellationError()) }
            else if let range = value.0.range {
                let payload = bytes.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
                received += UInt64(payload.count); value.1.resume(returning: payload)
            } else { value.1.resume(throwing: BackendContractError.invalidValue) }
        }
        finishInvalidationIfReady()
    }
    @MainActor func close() async {
        closeRequested = true
        for id in Array(pending.keys) { requestCancellation(id) }
        finishInvalidationIfReady()
        if !invalidated { await withCheckedContinuation { closeWaiters.append($0) } }
    }
    private func finishInvalidationIfReady() {
        guard closeRequested, pending.isEmpty else { return }
        invalidated = true
        let waiters = closeWaiters; closeWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
    @MainActor func state() async -> FixedRenditionHTTPState {
        .init(started: started, completed: completed, receivedBytes: received, bufferedPayloadBytes: 0, invalidated: invalidated)
    }
}
