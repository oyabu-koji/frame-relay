import Foundation

actor FixedRenditionRangeReader: RenditionByteReadingPort {
    private let command: RetrieveMediaCommand
    private let admission: any RenditionMediaAdmissionPort
    private let authorization: any RenditionRangeAuthorizationPort
    private let leases: RenditionReadLeases
    private let client: FixedRenditionHTTPClient
    private var tasks: [UUID: Task<Data, Error>] = [:]
    private var closed = false
    private var terminal: RenditionReadTerminal?
    private var closing: Task<RenditionReadTerminal, Error>?
    private var epoch: ReaderReconciliationEpoch?
    private var releaseFailed = false
    private var permit: RenditionScopePermit?
    private var readWaiters: [CheckedContinuation<Void, Never>] = []

    private init(command: RetrieveMediaCommand, admission: any RenditionMediaAdmissionPort,
         authorization: any RenditionRangeAuthorizationPort, leases: RenditionReadLeases,
         client: FixedRenditionHTTPClient) throws {
        guard command.identitiesMatch else { throw BackendContractError.identityMismatch }
        self.command = command; self.admission = admission; self.authorization = authorization
        self.leases = leases; self.client = client
    }

    static func open(command: RetrieveMediaCommand, admission: any RenditionMediaAdmissionPort,
                     authorization: any RenditionRangeAuthorizationPort, leases: RenditionReadLeases,
                     client: FixedRenditionHTTPClient, scope: RenditionMediaScope) async throws -> FixedRenditionRangeReader {
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
        let task = Task { try await perform(range) }
        tasks[id] = task
        defer {
            tasks.removeValue(forKey: id)
            if tasks.isEmpty {
                let waiters = readWaiters; readWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        let bytes = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard !closed else { throw CancellationError() }
        return bytes
    }

    private func perform(_ range: MediaByteRange) async throws -> Data {
        try Task.checkCancellation()
        try await admission.check(command.gate)
        guard let permit else { throw BackendContractError.wrongStage }
        try await permit.check()
        let proposed = RetrieveMediaCommand(gate: command.gate, distribution: command.distribution, range: range)
        let authorized = try await authorization.authorize(proposed)
        guard authorized.identitiesMatch, authorized.gate == command.gate, authorized.range == range,
              authorized.distribution.rendition == command.distribution.rendition,
              authorized.distribution.registration == command.distribution.registration, !closed else {
            throw BackendContractError.identityMismatch
        }
        let lease = try await leases.acquire(rendition: authorized.distribution.rendition,
            registration: authorized.distribution.registration, operation: command.gate.operation,
            context: .transport(command.gate.attempt))
        epoch = lease.epoch
        let outcome: Result<Data, Error>
        do {
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            try await leases.commit(.distribution(.init(command: .init(rawValue: UUID().uuidString),
                lease: lease, observation: .init(rawValue: 1), result: .succeeded(authorized.distribution))))
            try await admission.check(command.gate)
            try await permit.check()
            try await leases.check(lease)
            let bytes = try await client.read(authorized)
            try Task.checkCancellation()
            try await admission.check(command.gate)
            try await permit.check()
            try await leases.check(lease)
            guard !closed else { throw CancellationError() }
            outcome = .success(bytes)
        } catch { outcome = .failure(error) }
        // read() resumes only from URLSession's actual terminal callback. A
        // cancelled Task alone is never considered release of the transport.
        do { try await leases.release(lease) }
        catch { releaseFailed = true; throw error }
        return try outcome.get()
    }

    func close() async throws -> RenditionReadTerminal {
        if let terminal { return terminal }
        if let closing { return try await closing.value }
        closed = true
        let task = Task { try await finishClosing() }
        closing = task
        return try await task.value
    }

    private func finishClosing() async throws -> RenditionReadTerminal {
        let outstanding = Array(tasks.values)
        for task in outstanding { task.cancel() }
        await client.close()
        for task in outstanding { _ = await task.result }
        if !tasks.isEmpty { await withCheckedContinuation { readWaiters.append($0) } }
        guard !releaseFailed else { throw BackendContractError.unknownResult }
        let current = try await leases.currentEpoch()
        guard epoch == nil || epoch == current else { throw BackendContractError.staleGeneration }
        let result = await RenditionReadTerminal(epoch: current, started: client.started,
            completed: client.completed, bytes: client.receivedBytes, handlesClosed: client.invalidated)
        guard result.started == result.completed, result.handlesClosed else { throw BackendContractError.readersActive }
        terminal = result
        return result
    }
}
