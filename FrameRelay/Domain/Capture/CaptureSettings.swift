nonisolated enum CaptureCodec: String, Equatable, Hashable, Sendable, Codable {
    case proRes422LT
    case proRes422
    case proRes422Proxy
}

nonisolated enum CaptureLogEncoding: String, Equatable, Hashable, Sendable, Codable {
    case appleLog
    case appleLog2
}

/// A requested combination is not evidence that a device supports or applied it.
nonisolated struct CaptureConfiguration: Equatable, Hashable, Sendable, Codable {
    let camera: String
    let width: Int
    let height: Int
    let framesPerSecond: Int
    let codec: CaptureCodec
    let logEncoding: CaptureLogEncoding
    let stabilizationMode: String

    init(camera: String, width: Int, height: Int, framesPerSecond: Int,
         codec: CaptureCodec, logEncoding: CaptureLogEncoding, stabilizationMode: String) throws {
        guard !camera.isEmpty, width > 0, height > 0, framesPerSecond > 0,
              !stabilizationMode.isEmpty else { throw CaptureContractError.invalidValue }
        self.camera = camera
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.codec = codec
        self.logEncoding = logEncoding
        self.stabilizationMode = stabilizationMode
    }
}

nonisolated struct CaptureManualExposure: Equatable, Sendable, Codable {
    let shutter: CaptureRationalTime
    let iso: Double
    /// nil requests no aperture adjustment; it does not claim variable-aperture support.
    let aperture: Double?

    init(shutter: CaptureRationalTime, iso: Double, aperture: Double?) throws {
        guard shutter.ticks > 0, iso.isFinite, iso > 0,
              aperture.map({ $0.isFinite && $0 > 0 }) ?? true else {
            throw CaptureContractError.invalidValue
        }
        self.shutter = shutter
        self.iso = iso
        self.aperture = aperture
    }
}

/// There is intentionally no persisted WB lock or hidden product default.
nonisolated struct DesiredCaptureSettings: Equatable, Sendable, Codable {
    let configuration: CaptureConfiguration
    let exposure: CaptureManualExposure
    let zoom: Double

    init(configuration: CaptureConfiguration, exposure: CaptureManualExposure, zoom: Double) throws {
        guard zoom.isFinite, zoom > 0 else { throw CaptureContractError.invalidValue }
        self.configuration = configuration
        self.exposure = exposure
        self.zoom = zoom
    }
}

nonisolated struct CaptureManualLimits: Equatable, Sendable, Codable {
    let shutterSeconds: ClosedRange<Double>
    let iso: ClosedRange<Double>
    let aperture: CaptureCapability<ClosedRange<Double>>
    let zoom: ClosedRange<Double>
}

nonisolated struct CaptureCapabilities: Equatable, Sendable, Codable {
    let generation: CaptureGeneration
    let configurations: CaptureCapability<Set<CaptureConfiguration>>
    /// Manual/WB capabilities below belong only to this camera/format combination.
    let controlsForConfiguration: CaptureConfiguration?
    let manualControls: CaptureCapability<CaptureManualLimits>
    let whiteBalanceLock: CaptureCapability<Bool>
    /// Optional for old persisted observations; missing is unconfirmed, never support.
    var whiteBalanceRefresh: CaptureCapability<Bool>? = nil
}

nonisolated struct AppliedCaptureValues: Equatable, Sendable, Codable {
    let configuration: CaptureConfiguration
    let exposure: CaptureManualExposure
    let zoom: Double

    func matches(_ desired: DesiredCaptureSettings) -> Bool {
        // Readback quantization is not silently rounded into equality. A later adapter
        // must expose differences and any explicitly agreed comparison policy.
        configuration == desired.configuration && exposure == desired.exposure && zoom == desired.zoom
    }
}

nonisolated struct AppliedCaptureSettings: Equatable, Sendable, Codable {
    let generation: CaptureGeneration
    let operation: CaptureOperationID
    let values: CaptureObservation<AppliedCaptureValues>
}

nonisolated enum CaptureResourceReadiness: Equatable, Sendable, Codable {
    case checking
    case ready
    case unavailable(CaptureUnavailableReason)
}

nonisolated enum RecordingBlocker: Equatable, Sendable, Codable {
    case desiredSettingsMissing
    case capabilitiesUnqueried
    case unsupported(CaptureUnavailableReason)
    case capabilityUnavailable(CaptureUnavailableReason)
    case staleGeneration
    case configurationUnsupported
    case capabilityScopeMismatch
    case manualControlOutsideCapability
    case appliedValuesUnconfirmed
    case appliedValuesDiffer
    case cameraNotReady
    case audioNotValid
    case destinationNotReady
    case recordingResourcesNotReady
}

nonisolated struct CaptureReadiness: Equatable, Sendable, Codable {
    let generation: CaptureGeneration
    let desired: DesiredCaptureSettings?
    let capabilities: CaptureCapabilities
    let applied: AppliedCaptureSettings?
    let camera: CaptureResourceReadiness
    let audioInput: CaptureAudioInputState
    let destination: CaptureResourceReadiness
    let recordingResources: CaptureResourceReadiness

    /// Analysis/ND/person/WB-stability states are deliberately not REC dependencies.
    var blockers: [RecordingBlocker] {
        var result: [RecordingBlocker] = []
        guard let desired else { return [.desiredSettingsMissing] }
        if capabilities.generation != generation { result.append(.staleGeneration) }
        if capabilities.controlsForConfiguration != desired.configuration {
            result.append(.capabilityScopeMismatch)
        }
        switch capabilities.configurations {
        case .unqueried: result.append(.capabilitiesUnqueried)
        case .unsupported(let reason): result.append(.unsupported(reason))
        case .unavailable(let reason): result.append(.capabilityUnavailable(reason))
        case .supported(let configurations):
            if !configurations.contains(desired.configuration) { result.append(.configurationUnsupported) }
        }
        switch capabilities.manualControls {
        case .unqueried: result.append(.capabilitiesUnqueried)
        case .unsupported(let reason): result.append(.unsupported(reason))
        case .unavailable(let reason): result.append(.capabilityUnavailable(reason))
        case .supported(let limits):
            if !limits.iso.contains(desired.exposure.iso)
                || !limits.shutterSeconds.contains(desired.exposure.shutter.seconds)
                || !limits.zoom.contains(desired.zoom) {
                result.append(.manualControlOutsideCapability)
            }
            if let aperture = desired.exposure.aperture {
                if case .supported(let range) = limits.aperture, range.contains(aperture) {
                    // Explicitly supported; no substitution.
                } else {
                    result.append(.manualControlOutsideCapability)
                }
            }
        }
        switch capabilities.whiteBalanceLock {
        case .unqueried: result.append(.capabilitiesUnqueried)
        case .unsupported(let reason): result.append(.unsupported(reason))
        case .unavailable(let reason): result.append(.capabilityUnavailable(reason))
        case .supported(let supported):
            if !supported { result.append(.unsupported(.unsupported)) }
        }
        if let applied {
            if applied.generation != generation { result.append(.staleGeneration) }
            if let values = applied.values.value {
                if !values.matches(desired) { result.append(.appliedValuesDiffer) }
            } else { result.append(.appliedValuesUnconfirmed) }
        } else { result.append(.appliedValuesUnconfirmed) }
        if camera != .ready { result.append(.cameraNotReady) }
        if case .valid = audioInput {} else { result.append(.audioNotValid) }
        if destination != .ready { result.append(.destinationNotReady) }
        if recordingResources != .ready { result.append(.recordingResourcesNotReady) }
        return result
    }
}
