import Foundation

actor TemporaryRenditionReader: RenditionByteReadingPort {
    private let media: ManagedTemporaryMedia
    private let usage: TemporaryMediaUsage
    private var closed = false
    private var started = 0
    private var completed = 0
    private var bytes: UInt64 = 0
    private var tasks: [UUID: Task<Data, Error>] = [:]
    private var terminal: RenditionReadTerminal?
    private var tail: Task<Void, Never>?
    private var resultPayloads: [UUID: UInt64] = [:]
    private var closing: Task<RenditionReadTerminal, Error>?
    private var permit: RenditionScopePermit?
    private var workerCompleted = 0
    private var readWaiters: [CheckedContinuation<Void, Never>] = []

    private init(media: ManagedTemporaryMedia, usage: TemporaryMediaUsage) {
        self.media = media; self.usage = usage
    }
    static func open(media: ManagedTemporaryMedia, usage: TemporaryMediaUsage,
                     scope: RenditionMediaScope) async throws -> TemporaryRenditionReader {
        let value = TemporaryRenditionReader(media: media, usage: usage)
        let permit = try await scope.register(owner: .temporaryMedia) { try await value.close() }
        await value.activate(permit)
        return value
    }
    private func activate(_ permit: RenditionScopePermit) { self.permit = permit }
    func read(offset: UInt64, length: Int) async throws -> Data {
        guard let permit else { throw BackendContractError.wrongStage }
        try await permit.check()
        guard !closed else { throw CancellationError() }
        let id = UUID()
        let previous = tail
        let task = Task {
            defer { workerCompleted += 1 }
            await previous?.value
            try Task.checkCancellation()
            let value = try await media.read(usage, offset: offset, length: length)
            resultPayloads[id] = UInt64(value.count)
            return value
        }
        tail = Task { _ = await task.result }
        tasks[id] = task; started += 1
        defer {
            tasks.removeValue(forKey: id); completed += 1
            resultPayloads.removeValue(forKey: id)
            if tasks.isEmpty {
                let waiters = readWaiters; readWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        bytes += UInt64(value.count)
        return value
    }
    func bufferSnapshot() -> (activeReads: Int, payloadBytes: UInt64, hasSchedulingTail: Bool) {
        (tasks.count, resultPayloads.values.reduce(0, +), tail != nil)
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
            for task in outstanding { _ = await task.result }
        }
        await tail?.value
        tail = nil
        if !tasks.isEmpty { await withCheckedContinuation { readWaiters.append($0) } }
        guard started == completed, started == workerCompleted, resultPayloads.isEmpty else { throw BackendContractError.readersActive }
        guard case .succeeded = await media.releaseUsage(usage), let epoch = usage.epoch else {
            throw BackendContractError.unknownResult
        }
        let value = RenditionReadTerminal(epoch: epoch, started: started, completed: completed,
                                          bytes: bytes, handlesClosed: true)
        terminal = value
        return value
    }
}
