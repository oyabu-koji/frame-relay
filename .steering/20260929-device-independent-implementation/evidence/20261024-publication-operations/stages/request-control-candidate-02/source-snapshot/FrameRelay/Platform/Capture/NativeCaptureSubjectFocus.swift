import AVFoundation

/// Only focus properties are changed. Exposure, WB, zoom, format and stabilization
/// remain owned by their existing controllers. Readback is command evidence, not sharpness.
nonisolated enum NativeCaptureSubjectFocus {
    static func apply(_ action: CaptureSubjectFocusAction, to device: AVCaptureDevice) -> CaptureSubjectFocusAvailability {
        let plan = plan(action, continuousSupported: device.isFocusModeSupported(.continuousAutoFocus),
                        lockSupported: device.isFocusModeSupported(.locked), pointSupported: device.isFocusPointOfInterestSupported)
        guard let plan else { return .unsupported }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.autoFocus) || device.isFocusModeSupported(.continuousAutoFocus) {
                device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
                device.isFaceDrivenAutoFocusEnabled = plan.faceDriven
            }
            if let point = plan.point { device.focusPointOfInterest = CGPoint(x: point.x, y: point.y) }
            device.focusMode = plan.hold ? .locked : .continuousAutoFocus
            guard (!(device.isFocusModeSupported(.autoFocus) || device.isFocusModeSupported(.continuousAutoFocus))
                   || (!device.automaticallyAdjustsFaceDrivenAutoFocusEnabled && device.isFaceDrivenAutoFocusEnabled == plan.faceDriven)),
                  device.focusMode == (plan.hold ? .locked : .continuousAutoFocus),
                  plan.point.map({ device.focusPointOfInterest == CGPoint(x: $0.x, y: $0.y) }) ?? true else { return .failed }
            return .applied
        } catch { return .failed }
    }

    struct Plan: Equatable, Sendable {
        let hold: Bool
        let point: CaptureSubjectPoint?
        let faceDriven: Bool
    }

    /// Unsupported AF never silently becomes a lock, and selected-person AF never
    /// leaves automatic face switching enabled behind the selected point.
    static func plan(_ action: CaptureSubjectFocusAction, continuousSupported: Bool,
                     lockSupported: Bool, pointSupported: Bool) -> Plan? {
        switch action {
        case .hold: return lockSupported ? .init(hold: true, point: nil, faceDriven: false) : nil
        case .personPriority:
            return continuousSupported ? .init(hold: false, point: nil, faceDriven: true) : nil
        case .continuous(let point, let personDriven):
            guard continuousSupported, pointSupported, point.isValid else { return nil }
            return .init(hold: false, point: point, faceDriven: personDriven)
        }
    }
}
