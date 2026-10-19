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
    private var tail: Task<Data, Error>?
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
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            return try await media.read(usage, offset: offset, length: length)
        }
        tail = task
        tasks[id] = task; started += 1
        defer {
            tasks.removeValue(forKey: id); completed += 1
            if tasks.isEmpty {
                let waiters = readWaiters; readWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        let value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard !closed else { throw CancellationError() }
        bytes += UInt64(value.count)
        return value
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
        let outstanding = Array(tasks.values)
        for task in outstanding { task.cancel() }
        for task in outstanding { _ = await task.result }
        if !tasks.isEmpty { await withCheckedContinuation { readWaiters.append($0) } }
        guard started == completed, started == workerCompleted else { throw BackendContractError.readersActive }
        guard case .succeeded = await media.releaseUsage(usage), let epoch = usage.epoch else {
            throw BackendContractError.unknownResult
        }
        let value = RenditionReadTerminal(epoch: epoch, started: started, completed: completed,
                                          bytes: bytes, handlesClosed: true)
        terminal = value
        return value
    }
}
