@testable import FrameRelay
import Foundation

/// Await-inclusive stage latency. Concurrent reads may overlap; sums are not
/// wall-clock duration or measured CPU time.
nonisolated struct RenditionReadTiming: Codable, Sendable {
    var count = 0
    var totalMilliseconds: Double = 0
    var maximumMilliseconds: Double = 0
    mutating func record(_ elapsed: Duration) {
        let parts = elapsed.components
        let milliseconds = Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
        count += 1
        totalMilliseconds += milliseconds
        maximumMilliseconds = max(maximumMilliseconds, milliseconds)
    }
}

nonisolated struct RenditionReadDiagnostics: Codable, Sendable {
    let requestedReads: Int
    let requestedBytes: UInt64
    let activeReads: Int
    /// Logical payload retained by active read tasks; excludes SDK memory.
    let bufferedResultPayloadBytes: UInt64
    let peakBufferedResultPayloadBytes: UInt64
    let cacheHits: Int
    let cachePayloadBytes: UInt64
    let peakCachePayloadBytes: UInt64
    let pendingResponsePayloadBytes: UInt64
    let peakPendingResponsePayloadBytes: UInt64
    let timings: [String: RenditionReadTiming]
}

actor FixedRenditionRangeReader: RenditionByteReadingPort {
    private enum Stage: String, CaseIterable {
        case total, admission, authorization, leaseAcquire, distributionCommit, currentCheck, httpRead, leaseRelease
    }
    private let command: RetrieveMediaCommand
    private let admission: any RenditionMediaAdmissionPort
    private let authorization: any RenditionRangeAuthorizationPort
    private let leases: RenditionReadLeases
    private let client: any FixedRenditionHTTPTransport
    private var tasks: [UUID: Task<Data, Error>] = [:]
    private var closed = false
    private var terminal: RenditionReadTerminal?
    private var closing: Task<RenditionReadTerminal, Error>?
    private var epoch: ReaderReconciliationEpoch?
    private var releaseFailed = false
    private var permit: RenditionScopePermit?
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestedReads = 0
    private var requestedBytes: UInt64 = 0
    private var resultPayloads: [UUID: UInt64] = [:]
    private var peakResultPayloadBytes: UInt64 = 0
    private var timings: [Stage: RenditionReadTiming] = [:]
    private var tail: Task<Void, Never>?
    private var cache: CachedRange?
    private var cacheHits = 0
    private var peakCachePayloadBytes: UInt64 = 0
    private var pendingResponsePayloadBytes: UInt64 = 0
    private var peakPendingResponsePayloadBytes: UInt64 = 0

    private init(command: RetrieveMediaCommand, admission: any RenditionMediaAdmissionPort,
         authorization: any RenditionRangeAuthorizationPort, leases: RenditionReadLeases,
         client: any FixedRenditionHTTPTransport) throws {
        guard command.identitiesMatch else { throw BackendContractError.identityMismatch }
        self.command = command; self.admission = admission; self.authorization = authorization
        self.leases = leases; self.client = client
    }

    static func open(command: RetrieveMediaCommand, admission: any RenditionMediaAdmissionPort,
                     authorization: any RenditionRangeAuthorizationPort, leases: RenditionReadLeases,
                     client: any FixedRenditionHTTPTransport, scope: RenditionMediaScope) async throws -> FixedRenditionRangeReader {
        guard command.distribution.rendition.original == scope.original,
              try await leases.currentEpoch() == scope.epoch else { throw BackendContractError.identityMismatch }
        let reader = try FixedRenditionRangeReader(command: command, admission: admission,
            authorization: authorization, leases: leases, client: client)
        do {
            let permit = try await scope.register(owner: .transport) { try await reader.close() }
            await reader.activate(permit)
            return reader
        } catch { await client.close(); throw error }
    }
    private func activate(_ permit: RenditionScopePermit) { self.permit = permit }

    func read(offset: UInt64, length: Int) async throws -> Data {
        guard let permit else { throw BackendContractError.wrongStage }
        try await permit.check()
        let size = command.distribution.rendition.deliveryContent.byteCount
        guard !closed, length > 0, length <= 65_536, offset < size, UInt64(length) <= size - offset else {
            throw BackendContractError.invalidValue
        }
        let id = UUID()
        let range = try MediaByteRange(lowerBound: offset, upperBound: offset + UInt64(length))
        requestedReads += 1; requestedBytes += UInt64(length)
        let previous = tail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await perform(range, readID: id)
        }
        // A scheduling dependency retains no Data result after completion.
        tail = Task { _ = await task.result }
        tasks[id] = task
        defer {
            tasks.removeValue(forKey: id)
            resultPayloads.removeValue(forKey: id)
            if tasks.isEmpty {
                let waiters = readWaiters; readWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        let bytes = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        return bytes
    }

    private func perform(_ range: MediaByteRange, readID: UUID) async throws -> Data {
        let began = ContinuousClock.now
        defer { timings[.total, default: .init()].record(began.duration(to: .now)) }
        try Task.checkCancellation()
        guard !releaseFailed else { throw BackendContractError.unknownResult }
        try await timed(.admission) { try await admission.check(command.gate) }
        guard let permit else { throw BackendContractError.wrongStage }
        try await permit.check()
        guard !closed else { throw CancellationError() }
        if let lease = cache?.lease, cacheCovers(range) {
            try await checkCurrent(lease, permit: permit)
            try Task.checkCancellation()
            guard !closed, cache?.lease == lease, cacheCovers(range) else { throw CancellationError() }
            cacheHits += 1
            return try slice(range, readID: readID)
        }
        // There is only one retained interval. Drop its bytes before releasing
        // its transport lease, and before beginning another real GET.
        try await discardCache()
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        let size = command.distribution.rendition.deliveryContent.byteCount
        let expanded = try MediaByteRange(lowerBound: range.lowerBound,
            upperBound: range.lowerBound + min(65_536, size - range.lowerBound))
        let proposed = RetrieveMediaCommand(gate: command.gate, distribution: command.distribution, range: expanded)
        let authorized = try await timed(.authorization) { try await authorization.authorize(proposed) }
        guard authorized.identitiesMatch, authorized.gate == command.gate, authorized.range == expanded,
              authorized.distribution.rendition == command.distribution.rendition,
              authorized.distribution.registration == command.distribution.registration, !closed else {
            throw BackendContractError.identityMismatch
        }
        let lease = try await timed(.leaseAcquire) {
            try await leases.acquire(rendition: authorized.distribution.rendition,
                registration: authorized.distribution.registration, operation: command.gate.operation,
                context: .transport(command.gate.attempt))
        }
        epoch = lease.epoch
        do {
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            try await timed(.distributionCommit) {
                try await leases.commit(.distribution(.init(command: .init(rawValue: UUID().uuidString),
                    lease: lease, observation: .init(rawValue: 1), result: .succeeded(authorized.distribution))))
            }
            try await checkCurrent(lease, permit: permit)
            let bytes = try await timed(.httpRead) { try await client.read(authorized) }
            pendingResponsePayloadBytes = UInt64(bytes.count)
            peakPendingResponsePayloadBytes = max(peakPendingResponsePayloadBytes, pendingResponsePayloadBytes)
            guard UInt64(bytes.count) == expanded.upperBound - expanded.lowerBound else {
                throw BackendContractError.identityMismatch
            }
            try Task.checkCancellation()
            try await checkCurrent(lease, permit: permit)
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            cache = CachedRange(range: expanded, bytes: bytes, lease: lease)
            pendingResponsePayloadBytes = 0
            peakCachePayloadBytes = max(peakCachePayloadBytes, UInt64(bytes.count))
            return try slice(range, readID: readID)
        } catch {
            // The do-scope's Data has unwound before any release await.
            if cache?.lease == lease { cache = nil }
            pendingResponsePayloadBytes = 0
            let failure = error
            try await release(lease)
            throw failure
        }
    }

    private func cacheCovers(_ range: MediaByteRange) -> Bool {
        guard let cache else { return false }
        return cache.range.lowerBound <= range.lowerBound && range.upperBound <= cache.range.upperBound
    }

    private func slice(_ range: MediaByteRange, readID: UUID) throws -> Data {
        guard let cache, cacheCovers(range) else { throw BackendContractError.identityMismatch }
        let lower = Int(range.lowerBound - cache.range.lowerBound)
        let upper = Int(range.upperBound - cache.range.lowerBound)
        let result = cache.bytes.subdata(in: lower..<upper)
        resultPayloads[readID] = UInt64(result.count)
        peakResultPayloadBytes = max(peakResultPayloadBytes, resultPayloads.values.reduce(0, +))
        return result
    }

    private func checkCurrent(_ lease: MediaReadLease, permit: RenditionScopePermit) async throws {
        try await timed(.currentCheck) {
            try await admission.check(command.gate)
            try await permit.check()
            try await leases.check(lease)
        }
    }

    private func release(_ lease: MediaReadLease) async throws {
        do { try await timed(.leaseRelease) { try await leases.release(lease) } }
        catch { releaseFailed = true; throw error }
    }

    private func discardCache() async throws {
        guard let lease = cache?.lease else { return }
        cache = nil
        try await release(lease)
    }

    private func timed<Value: Sendable>(_ stage: Stage, _ operation: () async throws -> Value) async rethrows -> Value {
        let began = ContinuousClock.now
        defer { timings[stage, default: .init()].record(began.duration(to: .now)) }
        return try await operation()
    }

    func diagnostics() -> RenditionReadDiagnostics {
        .init(requestedReads: requestedReads, requestedBytes: requestedBytes, activeReads: tasks.count,
              bufferedResultPayloadBytes: resultPayloads.values.reduce(0, +),
              peakBufferedResultPayloadBytes: peakResultPayloadBytes,
              cacheHits: cacheHits, cachePayloadBytes: UInt64(cache?.bytes.count ?? 0),
              peakCachePayloadBytes: peakCachePayloadBytes, pendingResponsePayloadBytes: pendingResponsePayloadBytes,
              peakPendingResponsePayloadBytes: peakPendingResponsePayloadBytes,
              timings: Dictionary(uniqueKeysWithValues: Stage.allCases.map { ($0.rawValue, timings[$0] ?? .init()) }))
    }

    func close() async throws -> RenditionReadTerminal {
        if let terminal { return terminal }
        if let closing { return try await closing.value }
        closed = true
        let task = Task { try await finishClosing() }
        closing = task
        do { let value = try await task.value; closing = nil; return value }
        catch { closing = nil; throw error }
    }

    private func finishClosing() async throws -> RenditionReadTerminal {
        do {
            let outstanding = Array(tasks.values)
            for task in outstanding { task.cancel() }
            await client.close()
            for task in outstanding { _ = await task.result }
        }
        await tail?.value
        tail = nil
        if !tasks.isEmpty { await withCheckedContinuation { readWaiters.append($0) } }
        try await discardCache()
        guard !releaseFailed else { throw BackendContractError.unknownResult }
        let current = try await leases.currentEpoch()
        guard epoch == nil || epoch == current else { throw BackendContractError.staleGeneration }
        let state = await client.state()
        guard state.bufferedPayloadBytes == 0, resultPayloads.isEmpty, pendingResponsePayloadBytes == 0 else {
            throw BackendContractError.readersActive
        }
        let result = RenditionReadTerminal(epoch: current, started: state.started,
            completed: state.completed, bytes: state.receivedBytes, handlesClosed: state.invalidated)
        guard result.started == result.completed, result.handlesClosed else { throw BackendContractError.readersActive }
        terminal = result
        return result
    }

    private struct CachedRange {
        let range: MediaByteRange
        let bytes: Data
        let lease: MediaReadLease
    }
}
