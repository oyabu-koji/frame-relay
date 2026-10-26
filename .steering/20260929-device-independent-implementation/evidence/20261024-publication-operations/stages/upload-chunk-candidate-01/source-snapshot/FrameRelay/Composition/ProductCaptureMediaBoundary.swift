import Foundation

@MainActor final class ProductCaptureMediaBoundary: CaptureMediaBoundaryPort {
    private let background: ProductBackgroundMediaFactory
    private let didChange: @Sendable () -> Void
    private let photoLocalStop: (@Sendable (CaptureMediaOwner) async -> CaptureMediaLocalStop)?
    private var photoStopTasks: [UUID: Task<CaptureMediaLocalStop, Never>] = [:]
    let admission: CaptureMediaAdmission

    init(background: ProductBackgroundMediaFactory,
         photoLocalStop: (@Sendable (CaptureMediaOwner) async -> CaptureMediaLocalStop)? = nil,
         didChange: @escaping @Sendable () -> Void = {}) {
        self.background = background; admission = background.captureAdmission; self.didChange = didChange
        self.photoLocalStop = photoLocalStop
    }

    func begin(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>) {
        admission.begin(owner, phases: phases)
        synchronize()
    }
    func update(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>) {
        admission.update(owner, phases: phases)
        synchronize()
    }
    func end(_ owner: CaptureMediaOwner) {
        admission.end(owner)
        synchronize()
    }
    func waitForLocalStop(_ owner: CaptureMediaOwner) async -> CaptureMediaLocalStop {
        let transport = await background.waitForCaptureLocalStop(owner)
        guard transport == .ready else { return transport }
        guard admission.snapshot().owners[owner] != nil else { return .cancelled }
        if let photoLocalStop {
            let photos = await waitForPhotoStop(owner, action: photoLocalStop)
            guard admission.snapshot().owners[owner] != nil else { return .cancelled }
            guard photos == .ready else { return photos }
            // Recheck background/local scope after the potentially long actual
            // PhotoKit completion; an old preflight return is never a REC grant.
            return await background.waitForCaptureLocalStop(owner)
        }
        return .ready // Existing non-Photos test boundaries retain their contract.
    }

    private func waitForPhotoStop(_ owner: CaptureMediaOwner,
        action: @escaping @Sendable (CaptureMediaOwner) async -> CaptureMediaLocalStop) async -> CaptureMediaLocalStop {
        let changes = admission.changes()
        let pair = AsyncStream<CaptureMediaLocalStop>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let actual = Task { [self] in
            let result = await action(owner)
            pair.continuation.yield(result); pair.continuation.finish()
            photoStopTasks.removeValue(forKey: id)
            return result
        }
        photoStopTasks[id] = actual
        let admission = self.admission
        let monitor = Task {
            for await _ in changes {
                if admission.snapshot().owners[owner] == nil {
                    pair.continuation.yield(.cancelled); pair.continuation.finish()
                    return
                }
            }
        }
        var iterator = pair.stream.makeAsyncIterator()
        let result = await iterator.next() ?? .unknown
        monitor.cancel()
        // Ending a REC request revokes only its waiter. The retained task still
        // joins accepted PhotoKit completion/FD closure; it is never cancelled.
        return admission.snapshot().owners[owner] == nil ? .cancelled : result
    }
    private func synchronize() {
        // Admission's synchronous lock has already been released by the caller.
        didChange()
        // Every invocation reads the current revision at the actual worker,
        // rather than queueing an obsolete begin/end snapshot as authority.
        Task { await background.synchronizeCapture() }
    }
}
