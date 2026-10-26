import Foundation

@MainActor final class ProductCaptureMediaBoundary: CaptureMediaBoundaryPort {
    private let background: ProductBackgroundMediaFactory
    let admission: CaptureMediaAdmission

    init(background: ProductBackgroundMediaFactory) {
        self.background = background; admission = background.captureAdmission
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
        // Every invocation reads the current revision at the actual worker,
        // rather than queueing an obsolete begin/end snapshot as authority.
        Task { await background.synchronizeCapture() }
    }
}
