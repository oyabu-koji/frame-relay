import Foundation

nonisolated enum BackgroundDownloadPinResult: Equatable, Sendable {
    case pinned(BackgroundDownloadArtifactReference)
    case refused
}

/// Called synchronously only by the native owner's actual-creation/callback
/// path. The private system URL and response object exist solely during pin.
nonisolated protocol BackgroundDownloadIngressPinningPort: Sendable {
    func bindKnownCreation(_ intent: BackgroundMediaTaskIntent, binding: BackgroundMediaTaskBinding) -> Bool
    func pinKnownCallback(binding: BackgroundMediaTaskBinding, location: URL, response: HTTPURLResponse) -> BackgroundDownloadPinResult
    func requestStop(_ binding: BackgroundMediaTaskBinding)
    /// Seal later pins, but do not abort an already pinned file's worker.
    func observeKnownTerminal(_ terminal: BackgroundMediaSDKTerminal)
}

nonisolated struct UnavailableBackgroundDownloadIngress: BackgroundDownloadIngressPinningPort {
    func bindKnownCreation(_ intent: BackgroundMediaTaskIntent, binding: BackgroundMediaTaskBinding) -> Bool { false }
    func pinKnownCallback(binding: BackgroundMediaTaskBinding, location: URL, response: HTTPURLResponse) -> BackgroundDownloadPinResult { .refused }
    func requestStop(_ binding: BackgroundMediaTaskBinding) {}
    func observeKnownTerminal(_ terminal: BackgroundMediaSDKTerminal) {}
}
