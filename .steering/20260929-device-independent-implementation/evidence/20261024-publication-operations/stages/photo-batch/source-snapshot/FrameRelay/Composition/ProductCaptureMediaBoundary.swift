import Foundation

@MainActor final class ProductCaptureMediaBoundary: CaptureMediaBoundaryPort {
    private let background: ProductBackgroundMediaFactory
    private let didChange: @Sendable () -> Void
    let admission: CaptureMediaAdmission

    init(background: ProductBackgroundMediaFactory, didChange: @escaping @Sendable () -> Void = {}) {
        self.background = background; admission = background.captureAdmission; self.didChange = didChange
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
        await background.waitForCaptureLocalStop(owner)
    }
    private func synchronize() {
        // Admission's synchronous lock has already been released by the caller.
        didChange()
        // Every invocation reads the current revision at the actual worker,
        // rather than queueing an obsolete begin/end snapshot as authority.
        Task { await background.synchronizeCapture() }
    }
}
