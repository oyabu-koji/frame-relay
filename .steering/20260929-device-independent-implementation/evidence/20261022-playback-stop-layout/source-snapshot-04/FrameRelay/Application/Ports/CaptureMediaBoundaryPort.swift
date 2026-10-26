import Foundation

nonisolated struct CaptureMediaOwner: Hashable, Sendable {
    let context: CaptureContext
    let visit: UUID
    let nonce: UUID
}

nonisolated enum CaptureMediaPhase: Hashable, Sendable { case recording, saving, recovery }
nonisolated enum CaptureMediaLocalStop: Equatable, Sendable { case ready, cancelled, unknown }

/// MainActor entry points synchronously close admission before their caller's
/// first suspension. Only the local-resource observation is asynchronous.
@MainActor protocol CaptureMediaBoundaryPort: Sendable {
    func begin(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>)
    func update(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>)
    func end(_ owner: CaptureMediaOwner)
    func waitForLocalStop(_ owner: CaptureMediaOwner) async -> CaptureMediaLocalStop
}
