import AVFoundation

nonisolated enum NativeCaptureStabilization {
    /// The same admission is used by both recording output candidates, including OFF.
    static func admission(output: ExplorationOutputCandidate, requested: String,
                          connectionExists: Bool, supportsStabilization: Bool) -> String? {
        guard connectionExists else { return "stabilization_\(output.rawValue)_connection_missing" }
        guard CaptureStabilizationCatalog.modes.contains(requested) else { return "stabilization_unknown_mode" }
        guard requested != "previewOptimized" else { return "stabilization_preview_only" }
        guard requested == "off" || supportsStabilization else { return "stabilization_connection_unsupported" }
        return nil
    }

    static func request(_ mode: AVCaptureVideoStabilizationMode, on connection: AVCaptureConnection?,
                        output: ExplorationOutputCandidate) throws {
        let name = ExplorationCaptureValues.stabilizationName(mode) ?? "unknown"
        if let reason = admission(output: output, requested: name, connectionExists: connection != nil,
                                  supportsStabilization: connection?.isVideoStabilizationSupported == true) {
            throw ExplorationIssue.capabilityUnconfirmed(reason)
        }
        connection?.preferredVideoStabilizationMode = mode
        // Request readback is not active-mode evidence.
        guard connection?.preferredVideoStabilizationMode == mode else { throw ExplorationIssue.appliedValuesDiffer }
    }
}
