import AVFoundation

/// Bounded SDK ramp ownership. A target is never extended to an endpoint merely
/// because a late readback arrives; the same boundary applies in both directions.
nonisolated struct NativeCaptureZoomRamp: Equatable {
    let start: Double
    let target: Double
    private(set) var hasStarted = false

    mutating func stopFactor(observed: Double, isRamping: Bool, tolerance: Double) -> Double? {
        guard observed.isFinite else { return nil }
        if isRamping || observed != start { hasStarted = true }
        let passed = target >= start ? observed >= target : observed <= target
        if passed { return target }
        if abs(target - observed) <= tolerance { return observed }
        return !isRamping && hasStarted ? observed : nil
    }
}

nonisolated struct NativeCaptureZoomCommandOrder {
    private(set) var highest: UInt64?
    mutating func admit(_ sequence: UInt64) -> Bool {
        guard highest.map({ sequence > $0 }) ?? true else { return false }
        highest = sequence
        return true
    }
}

nonisolated enum NativeCaptureZoom {
    static func stops(range: ClosedRange<Double>, upscale: Double,
                      secondary: [Double], switches: [Double]) -> [CaptureZoomStop] {
        var values: [CaptureZoomStop] = [.init(factor: range.lowerBound, basis: .nativeMinimum)]
        values += switches.map { .init(factor: $0, basis: .lensSwitch) }
        values += secondary.map { .init(factor: $0, basis: .secondaryNativeResolution) }
        values.append(.init(factor: upscale, basis: .upscaleThreshold))
        var seen = Set<String>()
        return values.filter { $0.factor.isFinite && range.contains($0.factor) && seen.insert($0.id).inserted }
            .sorted { $0.factor == $1.factor ? $0.basis.rawValue < $1.basis.rawValue : $0.factor < $1.factor }
    }

    static func framingChanged(_ previous: CaptureStabilizationSnapshot?, _ current: CaptureStabilizationSnapshot) -> Bool {
        guard let previous else { return true }
        return previous.generation != current.generation || previous.camera != current.camera
            || previous.activePhysicalCamera != current.activePhysicalCamera || previous.formatID != current.formatID
            || previous.width != current.width || previous.height != current.height || previous.zoom != current.zoom
            || previous.activeMode.value != current.activeMode.value || previous.requestedMode != current.requestedMode
            || previous.preferredMode != current.preferredMode || previous.connection != current.connection
    }

    /// cancelVideoZoomRamp decelerates. Assigning the already observed value also
    /// ends the ramp, so a user stop cannot keep drifting toward the old target.
    static func stop(_ device: AVCaptureDevice, at factor: Double) {
        device.cancelVideoZoomRamp()
        device.videoZoomFactor = CGFloat(min(max(factor, Double(device.minAvailableVideoZoomFactor)),
                                            Double(device.maxAvailableVideoZoomFactor)))
    }
}
