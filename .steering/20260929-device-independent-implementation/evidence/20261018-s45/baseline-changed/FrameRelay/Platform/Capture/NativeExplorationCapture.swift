import AVFoundation
import Dispatch

/// Both output candidates use this serial SDK owner. Samples never enter View state.
actor NativeExplorationCapture: ExplorationDevicePort, ProductCaptureDevicePort {
    nonisolated let queue = DispatchSerialQueue(label: "FrameRelay.Exploration.Capture")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let candidate: ExplorationOutputCandidate
    private let originals: any ExplorationOriginalDestinationPort
    private let eventStream: AsyncStream<ExplorationDeviceEvent>
    private let eventContinuation: AsyncStream<ExplorationDeviceEvent>.Continuation
    private let captureStream: AsyncStream<CaptureIOEvent>
    private let captureContinuation: AsyncStream<CaptureIOEvent>.Continuation
    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var deviceClock: CMClock?
    private var devices: [String: AVCaptureDevice] = [:]
    private var movie: AVCaptureMovieFileOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var microphoneInput: AVCaptureDeviceInput?
    private var audioObservation = NativeCaptureAudioObservation(beganAt: ProcessInfo.processInfo.systemUptime)
    private let audioPolicy: ProductCaptureAudioPolicy?
    private let audioStream: AsyncStream<ProductCaptureAudioSnapshot>
    private let audioContinuation: AsyncStream<ProductCaptureAudioSnapshot>.Continuation
    private let stabilizationStream: AsyncStream<CaptureStabilizationSnapshot>
    private let stabilizationContinuation: AsyncStream<CaptureStabilizationSnapshot>.Continuation
    private var stabilizationObservations: [NSKeyValueObservation] = []
    private var stabilizationSequence: UInt64 = 0
    private var latestStabilization: CaptureStabilizationSnapshot?
    private var preparedStabilizationFormatID: String?
    private var audioMonitorTask: Task<Void, Never>?
    private var audioRecoveryRequest: ProductCaptureAudioRecoveryRequest?
    private var latestAudioRecoveryRequest: ProductCaptureAudioRecoveryRequest?
    private var cancelledAudioRecovery: Set<UUID> = []
    private var audioRecoveryContinuation: CheckedContinuation<CaptureAudioRecoveryOutcome, Never>?
    private var sampleDelegate: ExplorationSampleDelegate?
    private var movieDelegate: ExplorationMovieDelegate?
    private struct Preparation {
        let desired: DesiredCaptureSettings
        let generation: CaptureGeneration
        let operation: CaptureOperationID
        let trial: ExplorationTicket?
    }
    private var preparation: Preparation?
    private var activeIntent: RecordingIntent?
    private var activeToken: CaptureCommandToken?
    private var wbOrder: ExplorationWBCommandOrder?
    private var whiteBalanceObservation: NSKeyValueObservation?
    private var startAdmission = NativeRecordingStartAdmission()
    private var writer: AVAssetWriter?
    private var videoReceiver: AVAssetWriterInput.SampleBufferReceiver?
    private var audioReceiver: AVAssetWriterInput.SampleBufferReceiver?
    private var writerURL: URL?
    private var sourceStart: CMTime?
    private var firstAccepted = false
    private var lastVideo: CMTime?
    private var lastAudio: CMTime?
    private var firstAudio: CMTime?
    private var audioCount: UInt64 = 0
    private var firstAudioArrival: CMTime?
    private var lastAudioArrival: CMTime?
    private var audioArrivalCount: UInt64 = 0
    private var audioSequence: UInt64 = 0
    private var isFinishing = false
    private var termination = NativeRecordingTermination()
    private var durationTask: Task<Void, Never>?

    init(candidate: ExplorationOutputCandidate, originals: any ExplorationOriginalDestinationPort,
         audioPolicy: ProductCaptureAudioPolicy? = nil) {
        self.candidate = candidate
        self.originals = originals
        self.audioPolicy = audioPolicy
        let stabilizationPair = AsyncStream<CaptureStabilizationSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stabilizationStream = stabilizationPair.stream
        stabilizationContinuation = stabilizationPair.continuation
        let audioPair = AsyncStream<ProductCaptureAudioSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        audioStream = audioPair.stream
        audioContinuation = audioPair.continuation
        // Only bounded control transitions and first/last sample facts are emitted.
        // Per-sample data and an unbounded Task-per-sample stream are intentionally absent.
        let eventPair = AsyncStream<ExplorationDeviceEvent>.makeStream(bufferingPolicy: .bufferingOldest(128))
        eventStream = eventPair.stream
        eventContinuation = eventPair.continuation
        let capturePair = AsyncStream<CaptureIOEvent>.makeStream(bufferingPolicy: .bufferingOldest(64))
        captureStream = capturePair.stream
        captureContinuation = capturePair.continuation
    }

    func events() -> AsyncStream<CaptureIOEvent> { captureStream }
    func explorationEvents() -> AsyncStream<ExplorationDeviceEvent> { eventStream }

    func stabilizationSnapshots() -> AsyncStream<CaptureStabilizationSnapshot> { stabilizationStream }
    func audioSnapshots() -> AsyncStream<ProductCaptureAudioSnapshot> { audioStream }
    func productEvents() -> AsyncStream<ExplorationDeviceEvent> { eventStream }
    func previewSource() -> (any ProductCapturePreviewSource)? { session.map(NativeCapturePreviewSource.init) }
    func discover() throws -> [ExplorationCameraDescription] { try discover(stableIDs: false) }
    func discoverCameras() throws -> [ExplorationCameraDescription] { try discover(stableIDs: true) }

    private func discover(stableIDs: Bool) throws -> [ExplorationCameraDescription] {
        #if targetEnvironment(simulator)
        throw ExplorationIssue.simulatorHasNoVerifiedCamera
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw ExplorationIssue.permissionDenied
        }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [
            .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
            .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera,
            .builtInTrueDepthCamera, .builtInLiDARDepthCamera, .external
        ], mediaType: .video, position: .unspecified)
        devices.removeAll()
        return discovery.devices.enumerated().map { index, device in
            let id = stableIDs ? device.uniqueID : "camera-\(index + 1)"
            devices[id] = device
            let formats = device.formats.enumerated().map { index, format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return ExplorationFormatDescription(
                    id: stableIDs ? "current-format-\(index + 1)" : "format-\(index + 1)", width: Int(dimensions.width), height: Int(dimensions.height),
                    frameRateRanges: format.videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate },
                    logEncodings: [CaptureLogEncoding.appleLog, .appleLog2].filter {
                        format.supportedColorSpaces.contains(ExplorationCaptureValues.colorSpace($0))
                    },
                    stabilizationModes: ExplorationCaptureValues.stabilizationModes.compactMap { name, mode in
                        mode == .off || format.isVideoStabilizationModeSupported(mode) ? name : nil
                    })
            }
            return ExplorationCameraDescription(id: id, label: device.localizedName,
                                                isVirtual: device.isVirtualDevice, formats: formats)
        }
        #endif
    }

    func prepare(_ request: ExplorationPreparation) async throws -> ExplorationPrepared {
        guard request.ticket.validationIssues.isEmpty else { throw ExplorationIssue.settingsInvalid }
        if let issue = ExplorationDisplayBoundary.issue(for: request.ticket.display) { throw issue }
        return try await prepare(.init(desired: request.ticket.desired, generation: request.generation,
                                       operation: request.operation, trial: request.ticket))
    }

    func prepare(_ request: ProductCapturePreparation) async throws -> ExplorationPrepared {
        guard ProductCapturePreferences(desired: request.desired).isValid else { throw ExplorationIssue.settingsInvalid }
        return try await prepare(.init(desired: request.desired, generation: request.generation,
                                       operation: request.operation, trial: nil))
    }

    private func prepare(_ request: Preparation) async throws -> ExplorationPrepared {
        #if targetEnvironment(simulator)
        throw ExplorationIssue.simulatorHasNoVerifiedCamera
        #else
        guard activeToken == nil, session == nil else { throw ExplorationIssue.operationInProgress }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw ExplorationIssue.permissionDenied }
        _ = try discover(stableIDs: request.trial == nil)
        let desired = request.desired
        guard let selected = devices[desired.configuration.camera] else {
            throw ExplorationIssue.capabilityUnconfirmed("camera_unavailable")
        }
        let format: AVCaptureDevice.Format
        if let ticket = request.trial {
            guard let index = Int(ticket.formatID.replacingOccurrences(of: "format-", with: "")),
                  index > 0, selected.formats.indices.contains(index - 1) else {
                throw ExplorationIssue.capabilityUnconfirmed("format_unavailable")
            }
            format = selected.formats[index - 1]
        } else {
            // Re-resolve current hardware formats by the complete wish; never persist an array index.
            guard let matching = selected.formats.first(where: { Self.matches($0, desired: desired) }) else {
                throw ExplorationIssue.capabilityUnconfirmed("format_log_fps_controls")
            }
            format = matching
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let fps = Double(desired.configuration.framesPerSecond)
        guard Int(dimensions.width) == desired.configuration.width, Int(dimensions.height) == desired.configuration.height,
              format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= fps && fps <= $0.maxFrameRate }),
              format.supportedColorSpaces.contains(ExplorationCaptureValues.colorSpace(desired.configuration.logEncoding)),
              let stabilization = ExplorationCaptureValues.stabilizationModes.first(where: {
                  $0.0 == desired.configuration.stabilizationMode
              })?.1,
              stabilization == .off || format.isVideoStabilizationModeSupported(stabilization),
              selected.isExposureModeSupported(.custom), selected.isWhiteBalanceModeSupported(.locked),
              selected.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else {
            throw ExplorationIssue.capabilityUnconfirmed("format_log_fps_controls")
        }
        let shutter = CMTime(value: desired.exposure.shutter.ticks, timescale: desired.exposure.shutter.timescale)
        let aperture = desired.exposure.aperture.map(Float.init) ?? AVCaptureDevice.currentLensAperture
        guard format.supportsExposureModeCustom(lensAperture: aperture, duration: shutter, iso: Float(desired.exposure.iso)),
              desired.zoom >= Double(selected.minAvailableVideoZoomFactor),
              desired.zoom <= Double(selected.maxAvailableVideoZoomFactor) else {
            throw ExplorationIssue.capabilityUnconfirmed("manual_values")
        }
        if desired.exposure.aperture != nil, format.minLensAperture == format.maxLensAperture {
            throw ExplorationIssue.capabilityUnconfirmed("variable_aperture")
        }
        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .inputPriority
        captureSession.automaticallyConfiguresCaptureDeviceForWideColor = false
        let videoInput = try AVCaptureDeviceInput(device: selected)
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            captureSession.commitConfiguration()
            throw ExplorationIssue.capabilityUnconfirmed("microphone")
        }
        let audioInput = try AVCaptureDeviceInput(device: microphone)
        guard captureSession.canAddInput(videoInput), captureSession.canAddInput(audioInput) else {
            captureSession.commitConfiguration()
            throw ExplorationIssue.capabilityUnconfirmed("audio_video_inputs")
        }
        captureSession.addInput(videoInput)
        captureSession.addInput(audioInput)
        microphoneInput = audioInput
        try selected.lockForConfiguration()
        selected.activeFormat = format
        guard desired.zoom >= Double(selected.minAvailableVideoZoomFactor),
              desired.zoom <= Double(selected.maxAvailableVideoZoomFactor) else {
            selected.unlockForConfiguration()
            captureSession.commitConfiguration()
            throw ExplorationIssue.capabilityUnconfirmed("zoom_in_selected_format")
        }
        selected.activeColorSpace = ExplorationCaptureValues.colorSpace(desired.configuration.logEncoding)
        selected.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(desired.configuration.framesPerSecond))
        selected.activeVideoMaxFrameDuration = selected.activeVideoMinFrameDuration
        selected.videoZoomFactor = CGFloat(desired.zoom)
        selected.whiteBalanceMode = .continuousAutoWhiteBalance
        selected.unlockForConfiguration()
        do {
            try configureOutput(session: captureSession, stabilization: stabilization)
            captureSession.commitConfiguration()
            session = captureSession
            device = selected
            deviceClock = videoInput.ports.first(where: { $0.mediaType == .video })?.clock
            preparation = request
            wbOrder = ExplorationWBCommandOrder(generation: request.generation)
            startAdmission = NativeRecordingStartAdmission()
            audioObservation.reset(at: ProcessInfo.processInfo.systemUptime)
            captureSession.startRunning()
            startAudioMonitoring(generation: request.generation)
            startStabilizationObservation(generation: request.generation)
            try selected.lockForConfiguration()
            let appliedTime: CMTime = await withCheckedContinuation { continuation in
                selected.setExposureModeCustom(lensAperture: aperture, duration: shutter, iso: Float(desired.exposure.iso)) {
                    continuation.resume(returning: $0)
                }
                selected.unlockForConfiguration()
            }
            return try readPrepared(device: selected, format: format, at: appliedTime, request: request)
        } catch {
            if session == nil { captureSession.commitConfiguration() }
            clearStabilizationObservation()
            captureSession.stopRunning()
            session = nil
            device = nil
            preparation = nil
            throw error
        }
        #endif
    }

    private static func matches(_ format: AVCaptureDevice.Format, desired: DesiredCaptureSettings) -> Bool {
        let c = desired.configuration
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let fps = Double(c.framesPerSecond)
        guard Int(dimensions.width) == c.width, Int(dimensions.height) == c.height,
              format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= fps && fps <= $0.maxFrameRate }),
              format.supportedColorSpaces.contains(ExplorationCaptureValues.colorSpace(c.logEncoding)),
              let mode = ExplorationCaptureValues.stabilizationModes.first(where: { $0.0 == c.stabilizationMode })?.1,
              mode == .off || format.isVideoStabilizationModeSupported(mode) else { return false }
        let exposure = desired.exposure
        return format.supportsExposureModeCustom(lensAperture: exposure.aperture.map(Float.init) ?? AVCaptureDevice.currentLensAperture,
            duration: CMTime(value: exposure.shutter.ticks, timescale: exposure.shutter.timescale), iso: Float(exposure.iso))
    }

    private func configureOutput(session: AVCaptureSession, stabilization: AVCaptureVideoStabilizationMode) throws {
        if candidate == .movieFile {
            let output = AVCaptureMovieFileOutput()
            guard session.canAddOutput(output) else { throw ExplorationIssue.capabilityUnconfirmed("movie_output") }
            session.addOutput(output)
            guard let video = output.connection(with: .video), output.connection(with: .audio) != nil else {
                throw ExplorationIssue.capabilityUnconfirmed("movie_connections")
            }
            try NativeCaptureStabilization.request(stabilization, on: video, output: candidate)
            movie = output
        } else {
            let video = AVCaptureVideoDataOutput()
            guard session.canAddOutput(video) else {
                throw ExplorationIssue.capabilityUnconfirmed("sample_outputs")
            }
            session.addOutput(video)
            guard video.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) else {
                throw ExplorationIssue.capabilityUnconfirmed("ten_bit_capture")
            }
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange]
            video.alwaysDiscardsLateVideoFrames = true
            let delegate = ExplorationSampleDelegate(owner: self)
            video.setSampleBufferDelegate(delegate, queue: queue)
            try NativeCaptureStabilization.request(stabilization, on: video.connection(with: .video), output: candidate)
            sampleDelegate = delegate
            videoOutput = video
        }
        try configureAudioOutput(session)
    }

    private func configureAudioOutput(_ session: AVCaptureSession) throws {
        let output = AVCaptureAudioDataOutput()
        guard session.canAddOutput(output) else { throw ExplorationIssue.capabilityUnconfirmed("audio_observation_output") }
        session.addOutput(output)
        let delegate = sampleDelegate ?? ExplorationSampleDelegate(owner: self)
        output.setSampleBufferDelegate(delegate, queue: queue)
        sampleDelegate = delegate
        audioOutput = output
    }

    private func readPrepared(device: AVCaptureDevice, format: AVCaptureDevice.Format,
                              at time: CMTime, request: Preparation) throws -> ExplorationPrepared {
        let desired = request.desired
        let codec = ExplorationCaptureValues.codec(desired.configuration.codec)
        let videoConnection = movie?.connection(with: .video) ?? videoOutput?.connection(with: .video)
        let audioConnection = movie?.connection(with: .audio) ?? audioOutput?.connection(with: .audio)
        guard audioConnection?.isActive == true, audioConnection?.isEnabled == true,
              let videoConnection else { throw ExplorationIssue.capabilityUnconfirmed("active_audio_video") }
        if let movie {
            guard movie.availableVideoCodecTypes.contains(codec),
                  movie.supportedOutputSettingsKeys(for: videoConnection).contains(AVVideoCodecKey) else {
                throw ExplorationIssue.capabilityUnconfirmed("movie_codec")
            }
            movie.setOutputSettings([AVVideoCodecKey: codec], for: videoConnection)
            guard movie.outputSettings(for: videoConnection)[AVVideoCodecKey] as? String == codec.rawValue else {
                throw ExplorationIssue.appliedValuesDiffer
            }
        } else if videoOutput?.availableVideoCodecTypesForAssetWriter(writingTo: .mov).contains(codec) != true {
            throw ExplorationIssue.capabilityUnconfirmed("writer_codec")
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        guard device.activeColorSpace == ExplorationCaptureValues.colorSpace(desired.configuration.logEncoding),
              let mode = ExplorationCaptureValues.stabilizationModes.first(where: { $0.1 == videoConnection.activeVideoStabilizationMode }),
              device.activeVideoMinFrameDuration == device.activeVideoMaxFrameDuration,
              CMTimeGetSeconds(device.activeVideoMinFrameDuration) == 1 / Double(desired.configuration.framesPerSecond) else {
            throw ExplorationIssue.appliedValuesDiffer
        }
        let appliedConfiguration = try CaptureConfiguration(
            camera: desired.configuration.camera, width: Int(dimensions.width), height: Int(dimensions.height),
            framesPerSecond: desired.configuration.framesPerSecond, codec: desired.configuration.codec,
            logEncoding: desired.configuration.logEncoding, stabilizationMode: mode.0)
        let exposure = try CaptureManualExposure(
            shutter: .init(ticks: device.exposureDuration.value, timescale: device.exposureDuration.timescale),
            iso: Double(device.iso), aperture: desired.exposure.aperture == nil ? nil : Double(device.lensAperture))
        let values = AppliedCaptureValues(configuration: appliedConfiguration, exposure: exposure, zoom: Double(device.videoZoomFactor))
        let observationTime = ExplorationCaptureValues.time(time, clock: .captureDevice(camera: desired.configuration.camera), source: "exposure-completion")
        let applied = AppliedCaptureSettings(generation: request.generation, operation: request.operation,
                                            values: .observed(values, at: observationTime, method: .direct(source: "SDK-readback")))
        let aperture: CaptureCapability<ClosedRange<Double>> = format.minLensAperture < format.maxLensAperture
            ? .supported(Double(format.minLensAperture)...Double(format.maxLensAperture)) : .unsupported(.unsupported)
        let capabilities = CaptureCapabilities(
            generation: request.generation, configurations: .supported([desired.configuration]),
            controlsForConfiguration: desired.configuration,
            manualControls: .supported(.init(shutterSeconds: CMTimeGetSeconds(format.minExposureDuration)...CMTimeGetSeconds(format.maxExposureDuration),
                                             iso: Double(format.minISO)...Double(format.maxISO), aperture: aperture,
                                             zoom: Double(device.minAvailableVideoZoomFactor)...Double(device.maxAvailableVideoZoomFactor))),
            whiteBalanceLock: .supported(device.isWhiteBalanceModeSupported(.locked)),
            whiteBalanceRefresh: .supported(device.isWhiteBalanceModeSupported(.autoWhiteBalance)))
        observe("aperture_readback", context: nil, time: observationTime, detail: "lens_aperture=\(device.lensAperture)")
        publishStabilization(generation: request.generation)
        preparedStabilizationFormatID = latestStabilization?.formatID
        return ExplorationPrepared(capabilities: capabilities, applied: applied, audio: audioObservation.state,
                                   stabilization: latestStabilization)
    }

    private func startStabilizationObservation(generation: CaptureGeneration) {
        clearStabilizationObservation()
        guard let device, let connection = movie?.connection(with: .video) ?? videoOutput?.connection(with: .video),
              let session else { return }
        let changed: @Sendable () -> Void = { [weak self] in
            // Read current SDK facts on the serial owner, never retain a stale KVO value.
            Task { await self?.publishStabilization(generation: generation) }
        }
        stabilizationObservations = [
            connection.observe(\.activeVideoStabilizationMode, options: [.new]) { _, _ in changed() },
            connection.observe(\.preferredVideoStabilizationMode, options: [.new]) { _, _ in changed() },
            connection.observe(\.isActive, options: [.new]) { _, _ in changed() },
            connection.observe(\.isEnabled, options: [.new]) { _, _ in changed() },
            device.observe(\.videoZoomFactor, options: [.new]) { _, _ in changed() },
            device.observe(\.activeFormat, options: [.new]) { _, _ in changed() },
            device.observe(\.activePrimaryConstituent, options: [.new]) { _, _ in changed() },
            session.observe(\.isRunning, options: [.new]) { _, _ in changed() },
            session.observe(\.isInterrupted, options: [.new]) { _, _ in changed() }
        ]
        publishStabilization(generation: generation)
    }

    private func clearStabilizationObservation() {
        stabilizationObservations.forEach { $0.invalidate() }
        stabilizationObservations.removeAll()
        latestStabilization = nil
        preparedStabilizationFormatID = nil
    }

    private var stabilizationAllowsRecording: Bool {
        guard let preparation, let latestStabilization else { return false }
        return latestStabilization.matchesRecordingRequest(preparation.desired, generation: preparation.generation,
            output: candidate, preparedFormatID: preparedStabilizationFormatID)
    }

    private func publishStabilization(generation: CaptureGeneration) {
        guard let preparation, preparation.generation == generation, let device else { return }
        let connection = movie?.connection(with: .video) ?? videoOutput?.connection(with: .video)
        let requested = preparation.desired.configuration.stabilizationMode
        let state: CaptureStabilizationConnection
        if connection == nil { state = .missing }
        else if session?.isRunning != true || session?.isInterrupted == true || connection?.isActive != true || connection?.isEnabled != true { state = .inactive }
        else if requested != "off" && connection?.isVideoStabilizationSupported != true { state = .unsupported }
        else { state = .ready }
        let active: CaptureObservation<String>
        if state == .ready, let connection,
           let mode = ExplorationCaptureValues.stabilizationName(connection.activeVideoStabilizationMode) {
            active = .observed(mode, at: ExplorationCaptureValues.now(), method: .direct(source: "recording-connection-active-stabilization"))
        } else { active = .unavailable(state == .unsupported ? .unsupported : .notMeasured) }
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        stabilizationSequence += 1
        let snapshot = CaptureStabilizationSnapshot(generation: generation, sequence: stabilizationSequence,
            output: candidate, requestedMode: requested,
            preferredMode: connection.flatMap { ExplorationCaptureValues.stabilizationName($0.preferredVideoStabilizationMode) },
            activeMode: active, connection: state,
            camera: preparation.trial == nil ? device.uniqueID : (devices.first(where: { $0.value === device })?.key ?? ""),
            activePhysicalCamera: device.isVirtualDevice ? device.activePrimaryConstituent?.uniqueID : device.uniqueID,
            formatID: device.formats.firstIndex(where: { $0 === format }).map { "current-format-\($0 + 1)" } ?? "",
            width: Int(dimensions.width), height: Int(dimensions.height), zoom: Double(device.videoZoomFactor),
            uncorrectedFieldOfView: format.videoFieldOfView > 0 ? Double(format.videoFieldOfView) : nil)
        latestStabilization = snapshot
        stabilizationContinuation.yield(snapshot)
    }

    func submit(_ command: CaptureIOCommand) async -> CaptureCommandAcceptance {
        let token = command.token
        guard let preparation, token.context.generation == preparation.generation else {
            return .rejected(token, .evidenceMismatch)
        }
        do {
            switch command {
            case .lockCurrentWhiteBalance:
                guard activeToken == nil, wbOrder?.requestLock(token) == true else { return .rejected(token, .evidenceMismatch) }
                try lockCurrentWB(token)
            case .refreshAndLockWhiteBalance:
                guard activeToken?.context == token.context, !isFinishing, let device,
                      device.isWhiteBalanceModeSupported(.autoWhiteBalance),
                      wbOrder?.requestRefresh(token) == true else { return .rejected(token, .evidenceMismatch) }
                try refreshWhiteBalance(token, device: device)
            case .restoreAutomaticWhiteBalance:
                guard activeToken == nil, let device, wbOrder?.requestAutomatic(token) == true else {
                    return .rejected(token, .evidenceMismatch)
                }
                clearWhiteBalanceObservation()
                try device.lockForConfiguration()
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                device.unlockForConfiguration()
                guard wbOrder?.appliedAutomatic(token) == true else { return .rejected(token, .evidenceMismatch) }
                emit(.automaticWhiteBalanceRestored(token, ExplorationCaptureValues.now()))
            case .startRecording(_, let intent):
                publishStabilization(generation: preparation.generation)
                let admission = startAdmission.admit(token: token, intentContext: intent.context,
                    generation: preparation.generation, activeToken: activeToken,
                    ownsWhiteBalanceLock: wbOrder?.canStart(token.context) == true,
                    whiteBalanceLocked: device?.whiteBalanceMode == .locked,
                    sessionRunning: session?.isRunning == true && stabilizationAllowsRecording,
                    audioActive: currentAudioRoute() != nil && audioObservation.state.confirmedFailure == nil
                        && { if case .valid = audioObservation.state.input { return true }; return false }(),
                    observedAt: ExplorationCaptureValues.now())
                if case .rejected(let terminal) = admission {
                    if let terminal { emit(terminal) }
                    return .rejected(token, .evidenceMismatch)
                }
                // Reserve before the async hop, so STOP can mark this start as finishing.
                activeToken = token
                activeIntent = intent
                isFinishing = false
                let url = try await originals.reserve(original: intent.original)
                guard activeToken == token, !isFinishing else {
                    completeNeverStarted(token: token)
                    return .accepted(token)
                }
                try startRecording(url: url, token: token, intent: intent)
            case .stopRecording(_, let reason):
                guard activeToken == token else { return .rejected(token, .evidenceMismatch) }
                if case .audioFailure = reason { termination.recordAudioFailure() }
                else { termination.recordStop(reason) }
                stopRecording()
            }
            return .accepted(token)
        } catch {
            let reason = CaptureUnavailableReason.adapterFailure(code: "capture_command_failed")
            termination.recordCommandFailure(command, activeToken: activeToken, reason: reason)
            emit(.commandFailed(token, reason))
            if activeToken == token, writer == nil, movie?.isRecording != true { completeNeverStarted(token: token) }
            return .rejected(token, reason)
        }
    }

    private func lockCurrentWB(_ token: CaptureCommandToken) throws {
        guard let device else { throw ExplorationIssue.capabilityUnconfirmed("camera") }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        let gains = device.deviceWhiteBalanceGains
        let maximum = device.maxWhiteBalanceGain
        guard [gains.redGain, gains.greenGain, gains.blueGain].allSatisfy({ $0 >= 1 && $0 <= maximum }) else {
            throw ExplorationIssue.capabilityUnconfirmed("wb_gains")
        }
        let measured = ExplorationCaptureValues.now()
        observe("wb_lock_requested", context: token.context, time: measured, detail: "current_gains_no_stability_wait")
        // Current-gains locking remains supported when custom device gains are not.
        let requestedGains = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
            ? gains : AVCaptureDevice.currentWhiteBalanceGains
        device.setWhiteBalanceModeLocked(with: requestedGains) { [weak self] time in
            Task { await self?.whiteBalanceApplied(token: token, time: time) }
        }
    }

    private func refreshWhiteBalance(_ token: CaptureCommandToken, device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        clearWhiteBalanceObservation()
        // No initial notification: the previous locked state cannot finish this request.
        // SDK one-shot Auto returns to locked when its measurement finishes; no timer
        // or app-defined colour/stability threshold is used.
        whiteBalanceObservation = device.observe(\.whiteBalanceMode, options: [.new]) { [weak self] _, change in
            guard change.newValue == .locked else { return }
            Task { await self?.whiteBalanceMeasurementCompleted(token) }
        }
        device.whiteBalanceMode = .autoWhiteBalance
    }

    private func whiteBalanceMeasurementCompleted(_ token: CaptureCommandToken) {
        guard activeToken?.context == token.context, !isFinishing,
              wbOrder?.measurementCompleted(token) == true else { return }
        clearWhiteBalanceObservation()
        do { try lockCurrentWB(token) }
        catch { whiteBalanceFailedDuringRecording(token) }
    }

    private func clearWhiteBalanceObservation() {
        whiteBalanceObservation?.invalidate()
        whiteBalanceObservation = nil
    }

    private func whiteBalanceFailedDuringRecording(_ token: CaptureCommandToken) {
        clearWhiteBalanceObservation()
        let reason = CaptureUnavailableReason.adapterFailure(code: "wb_refix_failed")
        termination.recordFailure(reason)
        emit(.commandFailed(token, reason))
        // A failed camera lock must not strand recording behind a missing callback.
        finishStopRecording()
    }

    private func whiteBalanceApplied(token: CaptureCommandToken, time: CMTime) {
        guard wbOrder?.appliedLock(token) == true, let preparation, let device else { return }
        let actual = device.deviceWhiteBalanceGains
        guard device.whiteBalanceMode == .locked,
              let gains = try? CaptureWhiteBalanceGains(red: Double(actual.redGain), green: Double(actual.greenGain),
                                                        blue: Double(actual.blueGain)) else {
            let reason = CaptureUnavailableReason.adapterFailure(code: "wb_lock_readback_unconfirmed")
            emit(.commandFailed(token, reason))
            if activeToken != nil { termination.recordFailure(reason); finishStopRecording() }
            return
        }
        let applied = ExplorationCaptureValues.time(time, clock: .captureDevice(camera: preparation.desired.configuration.camera), source: "WB-completion")
        emit(.whiteBalanceLocked(token, .init(gains: gains, measuredAt: ExplorationCaptureValues.now(), appliedAt: applied)))
        if wbOrder?.shouldStopAfterLock(token) == true { finishStopRecording() }
        // Clock conversion is recorded as a derived mapping, not as an identical clock.
        if let deviceClock, let clock = session?.synchronizationClock {
            let mapped = CMSyncConvertTime(time, from: deviceClock, to: clock)
            observe("wb_session_clock_mapping", context: token.context,
                    time: ExplorationCaptureValues.time(mapped, clock: .captureSession(token.context.generation.session),
                                                        source: "CMSyncConvertTime", inferred: true,
                                                        evidence: [.init(rawValue: "\(token.context.capture.rawValue)-wb-device-time")]),
                    detail: "uncertainty_unmeasured")
        }
    }

    private func emit(_ event: CaptureIOEvent) {
        captureContinuation.yield(event)
        eventContinuation.yield(.capture(event))
    }

    private func observe(_ code: String, context: CaptureContext?, time: CaptureTimeObservation, detail: String) {
        eventContinuation.yield(.observation(.init(code: code, context: context, time: time, detail: detail)))
    }

    private func audioState(writing: CaptureAudioWriting) -> CaptureAudioState {
        audioObservation.writing(writing)
        return audioObservation.state
    }

    private func currentAudioRoute() -> String? {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let session, session.isRunning, !session.isInterrupted,
              let input = microphoneInput, input.device.isConnected,
              session.inputs.contains(where: { $0 === input }),
              audioOutput?.connection(with: .audio)?.isActive == true,
              audioOutput?.connection(with: .audio)?.isEnabled == true else { return nil }
        if let movie, movie.connection(with: .audio)?.isActive != true { return nil }
        return input.device.localizedName
    }

    private func publishAudio() {
        guard let preparation else { return }
        audioSequence += 1
        audioContinuation.yield(.init(generation: preparation.generation, capture: activeToken?.context.capture,
            sequence: audioSequence, state: audioObservation.state))
    }

    private func startAudioMonitoring(generation: CaptureGeneration) {
        audioMonitorTask?.cancel()
        audioMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                await self?.pollAudio(generation: generation)
            }
        }
    }

    private func pollAudio(generation: CaptureGeneration) {
        guard preparation?.generation == generation else { return }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            confirmAudioFailure(.permissionDenied)
        } else if session?.isInterrupted == true || microphoneInput?.device.isConnected == false {
            confirmAudioFailure(.routeInterrupted(.init(rawValue: "audio-route-interrupted")))
        } else if currentAudioRoute() == nil, case .valid = audioObservation.state.input {
            confirmAudioFailure(.routeInterrupted(.init(rawValue: "audio-route-unavailable")))
        } else if let policy = audioPolicy,
                  let failure = audioObservation.checkArrival(now: ProcessInfo.processInfo.systemUptime,
                      grace: policy.noArrivalGrace.seconds,
                      evidence: .init(rawValue: "audio-arrival-deadline-" + generation.session.rawValue)) {
            confirmAudioFailure(failure, alreadyLatched: true)
        }
        publishAudio()
    }

    fileprivate func isCurrentAudioOutput(_ output: AVCaptureOutput) -> Bool { output === audioOutput }

    fileprivate func observeAudio(_ sample: CMSampleBuffer, output: AVCaptureOutput) -> Bool {
        guard output === audioOutput, let preparation else { return false }
        guard audioObservation.receive(sample, generation: preparation.generation,
            route: currentAudioRoute(), now: ProcessInfo.processInfo.systemUptime) else {
            // Invalid/reordered buffers are not evidence of a live input. A fresh valid
            // sample must arrive before the configured deadline; level does not decide it.
            return false
        }
        if let request = audioRecoveryRequest, audioObservation.state.confirmedFailure == nil,
           case .valid(let route) = audioObservation.state.input {
            audioRecoveryRequest = nil
            let continuation = audioRecoveryContinuation
            audioRecoveryContinuation = nil
            publishAudio()
            continuation?.resume(returning: .validInput(route: route))
            observe("audio_recovery_input_observed", context: nil, time: ExplorationCaptureValues.now(),
                    detail: "attempt=\(request.ordinal);manual_REC_required")
        }
        return true
    }

    private func confirmAudioFailure(_ failure: CaptureAudioFailure, alreadyLatched: Bool = false) {
        guard alreadyLatched || audioObservation.state.confirmedFailure == nil else { return }
        audioObservation.fail(failure)
        // Record before notification: a user STOP may already be holding the final WB lock.
        if let token = activeToken {
            termination.recordAudioFailure(.adapterFailure(code: "confirmed_audio_failure"))
            audioSequence += 1
            emit(.audioObserved(token.context, sequence: audioSequence, audioObservation.state))
            stopRecording()
        }
        publishAudio()
        if audioRecoveryRequest != nil {
            audioRecoveryRequest = nil
            let continuation = audioRecoveryContinuation
            audioRecoveryContinuation = nil
            continuation?.resume(returning: .failed(failure))
        }
    }

    func recoverAudio(_ request: ProductCaptureAudioRecoveryRequest) async -> CaptureAudioRecoveryOutcome {
        guard !cancelledAudioRecovery.contains(request.operation),
              request.generation == preparation?.generation, activeToken == nil,
              audioRecoveryRequest == nil, let session else {
            return .failed(.routeInterrupted(.init(rawValue: "audio-recovery-wrong-owner")))
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            return .failed(.permissionDenied)
        }
        latestAudioRecoveryRequest = request
        audioRecoveryRequest = request
        // Only audio input/output are rebuilt. Camera, format, WB, and the movie output stay owned.
        session.beginConfiguration()
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        if let audioOutput { session.removeOutput(audioOutput) }
        if let microphoneInput { session.removeInput(microphoneInput) }
        audioOutput = nil; microphoneInput = nil
        do {
            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                throw ExplorationIssue.capabilityUnconfirmed("microphone")
            }
            let input = try AVCaptureDeviceInput(device: microphone)
            guard session.canAddInput(input) else { throw ExplorationIssue.capabilityUnconfirmed("audio_input") }
            session.addInput(input)
            microphoneInput = input
            try configureAudioOutput(session)
            session.commitConfiguration()
            audioObservation.reset(at: ProcessInfo.processInfo.systemUptime)
            publishAudio()
            return await withCheckedContinuation { audioRecoveryContinuation = $0 }
        } catch {
            session.commitConfiguration()
            audioRecoveryRequest = nil
            let failure = CaptureAudioFailure.routeInterrupted(.init(rawValue: "audio-reconfiguration-failed"))
            audioObservation.reset(at: ProcessInfo.processInfo.systemUptime)
            confirmAudioFailure(failure)
            return .failed(failure)
        }
    }

    func cancelAudioRecovery(_ request: ProductCaptureAudioRecoveryRequest) {
        cancelledAudioRecovery.insert(request.operation)
        guard latestAudioRecoveryRequest == request else { return }
        latestAudioRecoveryRequest = nil
        let failure = CaptureAudioFailure.routeInterrupted(.init(rawValue: "audio-recovery-cancelled"))
        audioObservation.fail(failure)
        audioRecoveryRequest = nil
        let continuation = audioRecoveryContinuation
        audioRecoveryContinuation = nil
        publishAudio()
        continuation?.resume(returning: .failed(failure))
    }

    private func sampleTime(_ time: CMTime, context: CaptureContext) -> CaptureTimeObservation {
        ExplorationCaptureValues.time(time, clock: .captureSession(context.generation.session), source: "capture-sample-PTS")
    }

    func shutDown() {
        guard activeToken == nil else { stopRecording(); return }
        clearWhiteBalanceObservation()
        clearStabilizationObservation()
        audioMonitorTask?.cancel(); audioMonitorTask = nil
        if let request = latestAudioRecoveryRequest { cancelAudioRecovery(request) }
        wbOrder = nil
        session?.stopRunning()
        videoOutput?.setSampleBufferDelegate(nil, queue: nil)
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        sampleDelegate = nil
        movieDelegate = nil
        movie = nil
        videoOutput = nil
        audioOutput = nil
        session = nil
        device = nil
        deviceClock = nil
        preparation = nil
        microphoneInput = nil
    }
}

extension NativeExplorationCapture {
    private func startRecording(url: URL, token: CaptureCommandToken, intent: RecordingIntent) throws {
        publishStabilization(generation: token.context.generation)
        guard stabilizationAllowsRecording else { throw ExplorationIssue.appliedValuesDiffer }
        guard let preparation else { throw ExplorationIssue.operationInProgress }
        sourceStart = nil
        firstAccepted = false
        lastVideo = nil
        lastAudio = nil
        firstAudio = nil
        audioCount = 0
        firstAudioArrival = nil
        lastAudioArrival = nil
        audioArrivalCount = 0
        termination.beginRecording()
        audioObservation.beginClip(movie: candidate == .movieFile)
        writerURL = url
        if let movie {
            if let trial = preparation.trial {
                movie.maxRecordedDuration = CMTime(value: trial.maximumDuration.ticks, timescale: trial.maximumDuration.timescale)
                guard trial.maximumFileBytes <= UInt64(Int64.max), trial.minimumRemainingBytes <= UInt64(Int64.max) else {
                    throw ExplorationIssue.trialLimitsInvalid
                }
                movie.maxRecordedFileSize = Int64(trial.maximumFileBytes)
                movie.minFreeDiskSpaceLimit = Int64(trial.minimumRemainingBytes)
            }
            // Product recordings keep SDK resource behavior; no exploratory duration/file caps.
            movie.metadata = CaptureCreationMetadata.items(capturedAt: intent.capturedAt)
            let delegate = ExplorationMovieDelegate(owner: self, token: token)
            movieDelegate = delegate
            movie.startRecording(to: url, recordingDelegate: delegate)
        } else {
            guard let videoOutput, let audioOutput,
                  var videoSettings = videoOutput.recommendedVideoSettings(
                    forVideoCodecType: ExplorationCaptureValues.codec(intent.desired.configuration.codec), assetWriterOutputFileType: .mov),
                  let audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) else {
                throw ExplorationIssue.capabilityUnconfirmed("recommended_writer_settings")
            }
            // SDK-specified Log tagging, paired with an actual source-attachment check below.
            // This is not a display transform and does not claim a verified saved Log file.
            var color: [String: Any] = [AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
            switch intent.desired.configuration.logEncoding {
            case .appleLog:
                color[AVVideoColorPrimariesKey] = AVVideoColorPrimaries_ITU_R_2020
                color[AVVideoLogTransferFunctionKey] = AVVideoLogTransferFunction_AppleLog
            case .appleLog2:
                color[AVVideoLogTransferFunctionKey] = AVVideoLogTransferFunction_AppleLog2
            }
            videoSettings[AVVideoColorPropertiesKey] = color
            let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
            assetWriter.metadata = CaptureCreationMetadata.items(capturedAt: intent.capturedAt)
            guard assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video),
                  assetWriter.canApply(outputSettings: audioSettings, forMediaType: .audio) else {
                throw ExplorationIssue.capabilityUnconfirmed("writer_settings")
            }
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            guard assetWriter.canAdd(videoInput), assetWriter.canAdd(audioInput) else {
                throw ExplorationIssue.capabilityUnconfirmed("writer_inputs")
            }
            videoReceiver = assetWriter.inputReceiver(for: videoInput)
            audioReceiver = assetWriter.inputReceiver(for: audioInput)
            try assetWriter.start()
            writer = assetWriter
        }
        guard let trial = preparation.trial else { return }
        let duration = trial.maximumDuration.seconds
        guard duration.isFinite, duration > 0, duration < Double(UInt64.max) / 1_000_000_000 else {
            throw ExplorationIssue.trialLimitsInvalid
        }
        // One bounded timer per explicit recording; no work is scheduled per sample.
        durationTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) }
            catch { return }
            await self?.trialDurationReached(token: token)
        }
    }

    private func trialDurationReached(token: CaptureCommandToken) {
        guard activeToken == token else { return }
        observe("trial_duration_reached", context: token.context, time: ExplorationCaptureValues.now(), detail: "ticket_bound_limit")
        stopRecording()
    }

    fileprivate func consume(_ sample: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>, isVideo: Bool) {
        guard let writer, let token = activeToken, !isFinishing else { return }
        let pts = sample.presentationTimeStamp
        let sampleCount = UInt64(max(sample.sampleCount, 0))
        guard sampleCount > 0, sample.sampleProperties.count == sample.sampleCount else {
            sampleFailure("sample_properties_missing", isAudio: !isVideo)
            return
        }
        guard pts.isNumeric else { sampleFailure("sample_pts_invalid", isAudio: !isVideo); return }
        var earliest = pts
        var latest = pts
        // A buffer PTS is not the last audio sample. Extract exact per-sample extrema
        // in the same epoch before ownership is transferred to the receiver.
        for property in sample.sampleProperties {
            let value = property.timing.presentationTimeStamp
            guard value.isNumeric, value.epoch == pts.epoch else {
                sampleFailure("sample_timeline_unconfirmed", isAudio: !isVideo)
                return
            }
            if CMTimeCompare(value, earliest) < 0 { earliest = value }
            if CMTimeCompare(value, latest) > 0 { latest = value }
        }
        if isVideo, !sourceLogMatches(sample) { sampleFailure("source_log_attachment_mismatch", isAudio: false); return }
        if sourceStart == nil {
            sourceStart = earliest
            writer.startSession(atSourceTime: earliest)
            observe("writer_timeline_start", context: token.context, time: sampleTime(earliest, context: token.context),
                    detail: "file_timeline_offset=source_start; first_buffer_not_per_track_start")
        }
        guard let sourceStart, sourceStart.epoch == earliest.epoch, CMTimeCompare(earliest, sourceStart) >= 0 else {
            sampleFailure("earlier_or_other_epoch_sample", isAudio: !isVideo)
            return
        }
        if !isVideo {
            if firstAudioArrival == nil { firstAudioArrival = earliest }
            lastAudioArrival = latest
            audioArrivalCount += sampleCount
        }
        do {
            let accepted: Bool
            if isVideo {
                guard let videoReceiver else { sampleFailure("video_receiver_missing", isAudio: false); return }
                accepted = try videoReceiver.appendImmediately(sample)
            } else {
                guard let audioReceiver else { sampleFailure("audio_receiver_missing", isAudio: true); return }
                accepted = try audioReceiver.appendImmediately(sample)
            }
            guard accepted else { sampleFailure("writer_backpressure", isAudio: !isVideo); return }
            // Setting a writer timeline is not evidence that a receiver accepted media.
            if !firstAccepted {
                firstAccepted = true
                emit(.recordingStarted(token, ExplorationCaptureValues.now()))
            }
            if isVideo {
                if lastVideo == nil {
                    observe("first_video_append_accepted", context: token.context, time: sampleTime(pts, context: token.context), detail: "not_file_commit")
                }
                lastVideo = latest
            } else {
                if firstAudio == nil { firstAudio = earliest }
                lastAudio = latest
                audioCount += sampleCount
                if let firstAudio {
                    let span = CaptureSampleSpan(first: sampleTime(firstAudio, context: token.context),
                                                 last: sampleTime(latest, context: token.context), count: audioCount)
                    audioObservation.writing(.accepted(span))
                }
            }
            try inspectTrialCapacity()
        } catch { sampleFailure("writer_append_or_capacity_check_failed", isAudio: !isVideo) }
    }

    private func sourceLogMatches(_ sample: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) -> Bool {
        guard let log = activeIntent?.desired.configuration.logEncoding else { return false }
        return sample.withUnsafeSampleBuffer { borrowed in
            guard let buffer = CMSampleBufferGetImageBuffer(borrowed),
                  let attachment = CVBufferCopyAttachment(buffer, kCVImageBufferLogTransferFunctionKey, nil) as? String,
                  let matrix = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String,
                  matrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String else { return false }
            switch log {
            case .appleLog:
                let primaries = CVBufferCopyAttachment(buffer, kCVImageBufferColorPrimariesKey, nil) as? String
                return attachment == kCVImageBufferLogTransferFunction_AppleLog as String
                    && primaries == kCVImageBufferColorPrimaries_ITU_R_2020 as String
            case .appleLog2:
                return attachment == kCVImageBufferLogTransferFunction_AppleLog2 as String
            }
        }
    }

    private func inspectTrialCapacity() throws {
        guard let ticket = preparation?.trial else { return }
        guard let url = writerURL else { throw ExplorationIssue.operationInProgress }
        let resources = try url.resourceValues(forKeys: [.fileSizeKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let free = resources.volumeAvailableCapacityForImportantUsage, free >= 0 else {
            throw ExplorationIssue.capacityInsufficient
        }
        if UInt64(free) <= ticket.minimumRemainingBytes || UInt64(max(resources.fileSize ?? 0, 0)) >= ticket.maximumFileBytes {
            termination.recordFailure(.resourceUnavailable)
            stopRecording()
        }
    }

    fileprivate func sampleFailure(_ code: String, isAudio: Bool) {
        guard let token = activeToken, !isFinishing else { return }
        if isAudio { termination.recordAudioFailure(.adapterFailure(code: code)) }
        else { termination.recordFailure(.adapterFailure(code: code)) }
        observe(code, context: token.context, time: ExplorationCaptureValues.now(), detail: "recording_stopped_no_retry")
        if isAudio {
            let failure = CaptureAudioFailure.writerFailed(.init(rawValue: "\(token.context.capture.rawValue)-\(code)"))
            confirmAudioFailure(failure)
        } else { emit(.commandFailed(token, .adapterFailure(code: code))) }
        stopRecording()
    }

    private func stopRecording() {
        guard let activeToken, !isFinishing else { return }
        switch wbOrder?.holdForStop(activeToken.context) ?? .stop {
        case .stop: finishStopRecording()
        case .waitForLock: break
        case .lockCurrent(let token):
            clearWhiteBalanceObservation()
            do { try lockCurrentWB(token) }
            catch { whiteBalanceFailedDuringRecording(token) }
        }
    }

    private func finishStopRecording() {
        guard activeToken != nil, !isFinishing else { return }
        isFinishing = true
        durationTask?.cancel()
        durationTask = nil
        if let movie, movie.isRecording {
            movie.stopRecording()
        } else if let writer {
            videoReceiver?.finish()
            audioReceiver?.finish()
            let token = activeToken
            writer.finishWriting { [weak self] in
                Task { await self?.writerFinished(expected: token) }
            }
        }
        // A stop during reserve() is completed by the start continuation, with no writer.
    }

    private func writerFinished(expected: CaptureCommandToken?) async {
        guard let writer, let token = activeToken, token == expected else { return }
        if writer.status == .completed, let firstAudio, let lastAudio {
            let span = CaptureSampleSpan(first: sampleTime(firstAudio, context: token.context),
                                         last: sampleTime(lastAudio, context: token.context), count: audioCount)
            audioObservation.writing(.completed(span))
            publishAudio()
        }
        let evidence = RecordingEndEvidence(
            writer: termination.writerFinished(completed: writer.status == .completed),
            ceasedAt: ExplorationCaptureValues.now(),
            lastVideo: lastVideo.map { sampleTime($0, context: token.context) } ?? .unavailable(.notMeasured),
            lastAudio: lastAudio.map { sampleTime($0, context: token.context) } ?? .unavailable(.notMeasured))
        await finish(token: token, evidence: evidence)
    }

    fileprivate func movieStarted(token: CaptureCommandToken, firstBuffer: CMTime) {
        guard activeToken == token else { return }
        emit(.recordingStarted(token, ExplorationCaptureValues.now()))
        observe("movie_first_buffer_pts", context: token.context, time: sampleTime(firstBuffer, context: token.context),
                detail: "per_video_audio_start_and_write_not_exposed")
        if isFinishing { movie?.stopRecording() }
    }

    fileprivate func movieFinished(token: CaptureCommandToken, failure: CaptureUnavailableReason?) async {
        guard activeToken == token else { return }
        let evidence = RecordingEndEvidence(writer: termination.movieFinished(failure: failure),
                                            ceasedAt: ExplorationCaptureValues.now(),
                                            lastVideo: .unavailable(.apiDoesNotExpose), lastAudio: .unavailable(.apiDoesNotExpose))
        await finish(token: token, evidence: evidence)
    }

    private func finish(token: CaptureCommandToken, evidence: RecordingEndEvidence) async {
        guard activeToken == token, let intent = activeIntent else { return }
        clearWhiteBalanceObservation()
        durationTask?.cancel()
        durationTask = nil
        activeToken = nil
        activeIntent = nil
        writer = nil
        videoReceiver = nil
        audioReceiver = nil
        isFinishing = false
        emit(.recordingEnded(token, evidence))
        do {
            let bytes = try await originals.byteCount(for: intent.original)
            eventContinuation.yield(.fileFinalized(.init(context: token.context, original: intent.original,
                                                          byteCount: bytes, finalizedAt: ExplorationCaptureValues.now())))
        } catch {
            observe("file_finalization_unconfirmed", context: token.context, time: ExplorationCaptureValues.now(), detail: "inspection_required")
        }
    }

    private func completeNeverStarted(token: CaptureCommandToken) {
        guard activeToken == token else { return }
        activeToken = nil
        activeIntent = nil
        isFinishing = false
        emit(.recordingEnded(token, .init(writer: .notStarted, ceasedAt: ExplorationCaptureValues.now(),
                                         lastVideo: .unavailable(.notMeasured), lastAudio: .unavailable(.notMeasured))))
    }
}

nonisolated private final class ExplorationSampleDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                                                          AVCaptureAudioDataOutputSampleBufferDelegate {
    weak var owner: NativeExplorationCapture?
    init(owner: NativeExplorationCapture) { self.owner = owner }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let owner else { return }
        let isVideo = output is AVCaptureVideoDataOutput
        guard isVideo || owner.assumeIsolated({ $0.isCurrentAudioOutput(output) }) else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            owner.assumeIsolated { $0.sampleFailure("sample_not_ready", isAudio: !isVideo) }
            return
        }
        if !isVideo, !owner.assumeIsolated({ $0.observeAudio(sampleBuffer, output: output) }) { return }
        let ready = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: sampleBuffer)
        // The delegate queue is the exact actor executor; the raw alias is never reused.
        owner.assumeIsolated { $0.consume(ready, isVideo: isVideo) }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let owner else { return }
        owner.assumeIsolated { $0.sampleFailure("capture_sample_dropped", isAudio: false) }
    }
}

nonisolated private final class ExplorationMovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    weak var owner: NativeExplorationCapture?
    let token: CaptureCommandToken
    init(owner: NativeExplorationCapture, token: CaptureCommandToken) { self.owner = owner; self.token = token }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, startPTS: CMTime,
                    from connections: [AVCaptureConnection]) {
        guard let owner else { return }
        let token = token
        Task { await owner.movieStarted(token: token, firstBuffer: startPTS) }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: (any Error)?) {
        let failure: CaptureUnavailableReason? = error.map { .adapterFailure(code: "movie_finish_\(($0 as NSError).code)") }
        guard let owner else { return }
        let token = token
        // Movie delegate has no specified callback queue. Only Sendable facts cross to the actor.
        Task { await owner.movieFinished(token: token, failure: failure) }
    }
}
