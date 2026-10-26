import Foundation

/// Process lifetime exclusion, not durable evidence of SDK start or completion.
/// A reopened intent still has no authority to add, even with an empty registry.
nonisolated final class PhotoSaveDispatchClaims: @unchecked Sendable {
    nonisolated static let shared = PhotoSaveDispatchClaims()
    private struct Key: Hashable { let store: RegistrationStoreIdentity; let operation: Data }
    private struct Entry { let owner: UUID; let input: Data; let claim: PhotoSaveDispatchClaim }
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var generations: [RegistrationStoreIdentity: UInt64] = [:]
    private var exhausted: Set<RegistrationStoreIdentity> = []

    func generation(for identity: RegistrationStoreIdentity) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        return exhausted.contains(identity) ? nil : (generations[identity] ?? 0)
    }

    func reserve(identity: RegistrationStoreIdentity, intent: PhotoRegistrationIntent,
                 receipt: TemporaryMediaReceipt?, owner: UUID) -> PhotoSaveDispatchClaim? {
        guard let input = try? Self.input(identity: identity, intent: intent, receipt: receipt) else { return nil }
        let key = Key(store: identity, operation: Data(intent.operation.rawValue.utf8))
        lock.lock(); defer { lock.unlock() }
        guard !exhausted.contains(identity) else { return nil }
        if let existing = entries[key] {
            guard existing.owner == owner, existing.input == input else { return nil }
            guard advance(identity) else { return nil }
            return existing.claim
        }
        guard advance(identity) else { return nil }
        let claim = PhotoSaveDispatchClaim(requested: intent)
        entries[key] = .init(owner: owner, input: input, claim: claim)
        return claim
    }

    private func advance(_ identity: RegistrationStoreIdentity) -> Bool {
        let previous = generations[identity] ?? 0
        guard previous != UInt64.max else { exhausted.insert(identity); return false }
        generations[identity] = previous + 1
        return true
    }

    private struct Coverage: Encodable {
        let id: TemporaryMediaID; let rendition: RenditionIdentity; let capturedAt: Date
        let ranges: [MediaByteRange]; let verifiedContent: ContentIdentity?
        let usage: TemporaryMediaUsage; let isReleased: Bool
    }
    private struct Input: Encodable {
        let identity: RegistrationStoreIdentity; let intent: PhotoRegistrationIntent; let receipt: Coverage?
    }
    private static func input(identity: RegistrationStoreIdentity, intent: PhotoRegistrationIntent,
                              receipt: TemporaryMediaReceipt?) throws -> Data {
        try intent.validate()
        let coverage = receipt.map { Coverage(id: $0.id, rendition: $0.rendition, capturedAt: $0.capturedAt,
            ranges: $0.ranges, verifiedContent: $0.verifiedContent, usage: $0.usage, isReleased: $0.isReleased) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Input(identity: identity, intent: intent, receipt: coverage))
    }
}

/// Mutable state is protected by this one lock. Continuation/yield callbacks
/// are always copied while locked and invoked after unlocking. The sole action
/// under lock is the bounded synchronous SDK registration owned by the winner.
nonisolated final class PhotoSaveDispatchClaim: @unchecked Sendable {
    private enum State: Equatable { case pending, cancelled, dispatched, finished }
    private let lock = NSLock()
    private let requested: PhotoRegistrationIntent
    private var boundBytes: Data?
    private var state = State.pending
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    fileprivate init(requested: PhotoRegistrationIntent) { self.requested = requested }

    func bind(_ intent: PhotoRegistrationIntent) -> Bool {
        guard PhotoSaveBatchValueValidation.exact(requested.operation, intent.operation),
              PhotoSaveBatchValueValidation.exact(requested.rendition, intent.rendition),
              PhotoSaveBatchValueValidation.exact(requested.media, intent.media),
              requested.capturedAt == intent.capturedAt,
              PhotoSaveBatchValueValidation.exact(requested.retryOf, intent.retryOf),
              requested.retryOf != nil || PhotoSaveBatchValueValidation.exact(requested.usage, intent.usage),
              let bytes = Self.bytes(intent) else { return false }
        lock.lock(); defer { lock.unlock() }
        if let boundBytes { return boundBytes == bytes }
        boundBytes = bytes
        return true
    }

    func matches(_ intent: PhotoRegistrationIntent) -> Bool {
        dispatchInput(for: intent) != nil
    }

    func dispatchInput(for intent: PhotoRegistrationIntent) -> Data? {
        guard let bytes = Self.bytes(intent) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return boundBytes == bytes ? bytes : nil
    }

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return state == .cancelled }

    @discardableResult func cancelBeforeStart() -> Bool {
        lock.lock()
        guard state == .pending else { lock.unlock(); return false }
        state = .cancelled
        let continuations = Array(observers.values)
        lock.unlock()
        for continuation in continuations { continuation.yield(()) }
        return true
    }

    func finish() {
        lock.lock()
        state = .finished
        let continuations = Array(observers.values)
        observers.removeAll()
        lock.unlock()
        for continuation in continuations { continuation.finish() }
    }

    func performIfPending(input: Data, action: () -> Void) -> PhotoSaveStartDisposition {
        lock.lock(); defer { lock.unlock() }
        guard boundBytes == input else { return .refused }
        if state == .cancelled { return .cancelledBeforeStart }
        guard state == .pending else { return .refused }
        state = .dispatched
        action()
        return .started
    }

    private static func bytes(_ intent: PhotoRegistrationIntent) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(intent)
    }

    func wakes() -> AsyncStream<Void> {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        pair.continuation.onTermination = { [weak self] _ in self?.removeObserver(id) }
        lock.lock(); observers[id] = pair.continuation; lock.unlock()
        pair.continuation.yield(())
        return pair.stream
    }

    func wake() {
        lock.lock(); let continuations = Array(observers.values); lock.unlock()
        for continuation in continuations { continuation.yield(()) }
    }

    private func removeObserver(_ id: UUID) { lock.lock(); observers.removeValue(forKey: id); lock.unlock() }
}
