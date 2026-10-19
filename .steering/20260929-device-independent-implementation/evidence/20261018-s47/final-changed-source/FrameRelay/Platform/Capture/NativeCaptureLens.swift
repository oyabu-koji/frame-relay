import AVFoundation

/// A late SDK completion acknowledges only its own request. It never restores an
/// older compensation over a newer manual value, including after session reset.
nonisolated struct NativeCaptureLensExposureOrder {
    struct Ticket: Equatable, Sendable {
        let revision: UInt64
        let manualRevision: UInt64
        let isManual: Bool
    }
    private(set) var revision: UInt64 = 0
    private(set) var manualRevision: UInt64 = 0
    private(set) var pending: Ticket?

    mutating func begin(manual: Bool) -> Ticket {
        revision += 1
        if manual { manualRevision += 1 }
        let ticket = Ticket(revision: revision, manualRevision: manualRevision, isManual: manual)
        pending = ticket
        return ticket
    }

    mutating func complete(_ ticket: Ticket) -> Bool {
        guard pending == ticket else { return false }
        pending = nil
        return true
    }

    mutating func invalidate() { revision += 1; pending = nil }
}

nonisolated enum NativeCaptureLens {
    struct Admission: Equatable, Sendable {
        let member: Bool
        let lockingSupported: Bool
        let formatMatches: Bool
        let stabilizationMatches: Bool
        let manualExposureSupported: Bool
        let compensationAvailable: Bool
        let movieOverrideDisabled: Bool

        var failure: String? {
            guard member else { return "lens_not_constituent" }
            guard lockingSupported else { return "lens_lock_unsupported" }
            guard compensationAvailable else { return "lens_iso_policy_unconfirmed" }
            guard formatMatches else { return "lens_format_unconfirmed" }
            guard stabilizationMatches else { return "lens_stabilization_unconfirmed" }
            guard manualExposureSupported else { return "lens_manual_exposure_unavailable" }
            guard movieOverrideDisabled else { return "lens_movie_override_active" }
            return nil
        }
    }

    static func effectiveDevice(_ device: AVCaptureDevice) -> AVCaptureDevice? {
        device.isVirtualDevice ? device.activePrimaryConstituent : device
    }

    static func isManual(_ device: AVCaptureDevice) -> Bool {
        device.exposureMode == .custom && !device.automaticallyAdjustsISO
            && !device.automaticallyAdjustsExposureDuration && !device.automaticallyAdjustsLensAperture
    }
}
