import AVFoundation
import Dispatch

/// Both output candidates use this serial SDK owner. Samples never enter View state.
actor NativeExplorationCapture: ExplorationDevicePort {
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
    private var sampleDelegate: ExplorationSampleDelegate?
    private var movieDelegate: ExplorationMovieDelegate?
    private var preparation: ExplorationPreparation?
    private var activeIntent: RecordingIntent?
    private var activeToken: CaptureCommandToken?
    private var wbOrder: ExplorationWBCommandOrder?
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
    private var stopFailure: CaptureUnavailableReason?
    private var durationTask: Task<Void, Never>?

    init(candidate: ExplorationOutputCandidate, originals: any ExplorationOriginalDestinationPort) {
        self.candidate = candidate
        self.originals = originals
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

    func discover() throws -> [ExplorationCameraDescription] {
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
            let id = "camera-\(index + 1)"
            devices[id] = device
            let formats = device.formats.enumerated().map { index, format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return ExplorationFormatDescription(
                    id: "format-\(index + 1)", width: Int(dimensions.width), height: Int(dimensions.height),
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
        #if targetEnvironment(simulator)
        throw ExplorationIssue.simulatorHasNoVerifiedCamera
        #else
        guard activeToken == nil, session == nil else { throw ExplorationIssue.operationInProgress }
        guard request.ticket.validationIssues.isEmpty else { throw ExplorationIssue.settingsInvalid }
        if let issue = ExplorationDisplayBoundary.issue(for: request.ticket.display) { throw issue }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw ExplorationIssue.permissionDenied }
        _ = try discover()
        let desired = request.ticket.desired
        guard let selected = devices[desired.configuration.camera],
              let formatIndex = Int(request.ticket.formatID.replacingOccurrences(of: "format-", with: "")),
              formatIndex > 0,
              selected.formats.indices.contains(formatIndex - 1) else {
            throw ExplorationIssue.capabilityUnconfirmed("camera_or_format")
        }
        let format = selected.formats[formatIndex - 1]
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
            captureSession.startRunning()
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
            captureSession.stopRunning()
            session = nil
            device = nil
            preparation = nil
            throw error
        }
        #endif
    }

    private func configureOutput(session: AVCaptureSession, stabilization: AVCaptureVideoStabilizationMode) throws {
        if candidate == .movieFile {
            let output = AVCaptureMovieFileOutput()
            guard session.canAddOutput(output) else { throw ExplorationIssue.capabilityUnconfirmed("movie_output") }
            session.addOutput(output)
            guard let video = output.connection(with: .video), output.connection(with: .audio) != nil else {
                throw ExplorationIssue.capabilityUnconfirmed("movie_connections")
            }
            video.preferredVideoStabilizationMode = stabilization
            movie = output
        } else {
            let video = AVCaptureVideoDataOutput()
            let audio = AVCaptureAudioDataOutput()
            guard session.canAddOutput(video), session.canAddOutput(audio) else {
                throw ExplorationIssue.capabilityUnconfirmed("sample_outputs")
            }
            session.addOutput(video)
            session.addOutput(audio)
            guard video.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) else {
                throw ExplorationIssue.capabilityUnconfirmed("ten_bit_capture")
            }
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange]
            video.alwaysDiscardsLateVideoFrames = true
            let delegate = ExplorationSampleDelegate(owner: self)
            video.setSampleBufferDelegate(delegate, queue: queue)
            audio.setSampleBufferDelegate(delegate, queue: queue)
            video.connection(with: .video)?.preferredVideoStabilizationMode = stabilization
            sampleDelegate = delegate
            videoOutput = video
            audioOutput = audio
        }
    }

    private func readPrepared(device: AVCaptureDevice, format: AVCaptureDevice.Format,
                              at time: CMTime, request: ExplorationPreparation) throws -> ExplorationPrepared {
        let desired = request.ticket.desired
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
            whiteBalanceLock: .supported(device.isWhiteBalanceModeSupported(.locked)))
        observe("aperture_readback", context: nil, time: observationTime, detail: "lens_aperture=\(device.lensAperture)")
        return ExplorationPrepared(capabilities: capabilities, applied: applied, audio: audioState(writing: .notStarted))
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
                // P10 binds the explicit remeasurement interval; never fake a new Auto measurement.
                return .rejected(token, .adapterFailure(code: "wb_refresh_interval_unbound"))
            case .restoreAutomaticWhiteBalance:
                guard activeToken == nil, let device, wbOrder?.requestAutomatic(token) == true else {
                    return .rejected(token, .evidenceMismatch)
                }
                try device.lockForConfiguration()
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                device.unlockForConfiguration()
                guard wbOrder?.appliedAutomatic(token) == true else { return .rejected(token, .evidenceMismatch) }
                emit(.automaticWhiteBalanceRestored(token, ExplorationCaptureValues.now()))
            case .startRecording(_, let intent):
                guard activeToken == nil, intent.context == token.context, wbOrder?.canStart(token.context) == true,
                      device?.whiteBalanceMode == .locked, session?.isRunning == true,
                      (movie?.connection(with: .audio) ?? audioOutput?.connection(with: .audio))?.isActive == true else {
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
                if case .audioFailure = reason { stopFailure = .interrupted }
                stopRecording()
            }
            return .accepted(token)
        } catch {
            emit(.commandFailed(token, .adapterFailure(code: "capture_command_failed")))
            if activeToken == token, writer == nil, movie?.isRecording != true { completeNeverStarted(token: token) }
            return .rejected(token, .adapterFailure(code: "capture_command_failed"))
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
        let values = try CaptureWhiteBalanceGains(red: Double(gains.redGain), green: Double(gains.greenGain), blue: Double(gains.blueGain))
        let measured = ExplorationCaptureValues.now()
        device.setWhiteBalanceModeLocked(with: gains) { [weak self] time in
            Task { await self?.whiteBalanceApplied(token: token, gains: values, measured: measured, time: time) }
        }
    }

    private func whiteBalanceApplied(token: CaptureCommandToken, gains: CaptureWhiteBalanceGains,
                                     measured: CaptureTimeObservation, time: CMTime) {
        guard wbOrder?.appliedLock(token) == true, let preparation else { return }
        let applied = ExplorationCaptureValues.time(time, clock: .captureDevice(camera: preparation.ticket.desired.configuration.camera), source: "WB-completion")
        emit(.whiteBalanceLocked(token, .init(gains: gains, measuredAt: measured, appliedAt: applied)))
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
        let arrival: CaptureAudioArrival
        if let firstAudioArrival, let lastAudioArrival, let context = activeToken?.context {
            arrival = .received(.init(first: sampleTime(firstAudioArrival, context: context), last: sampleTime(lastAudioArrival, context: context), count: audioArrivalCount))
        } else { arrival = .unavailable(candidate == .movieFile ? .apiDoesNotExpose : .notMeasured) }
        return CaptureAudioState(level: .unavailable(.adapterFailure(code: "level_measurement_not_implemented")),
                                 input: .valid(route: "configured-capture-audio-input"), arrival: arrival, writing: writing)
    }

    private func sampleTime(_ time: CMTime, context: CaptureContext) -> CaptureTimeObservation {
        ExplorationCaptureValues.time(time, clock: .captureSession(context.generation.session), source: "capture-sample-PTS")
    }

    func shutDown() {
        guard activeToken == nil else { stopRecording(); return }
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
    }
}

extension NativeExplorationCapture {
    private func startRecording(url: URL, token: CaptureCommandToken, intent: RecordingIntent) throws {
        guard let preparation else { throw ExplorationIssue.ticketMissing }
        sourceStart = nil
        firstAccepted = false
        lastVideo = nil
        lastAudio = nil
        firstAudio = nil
        audioCount = 0
        firstAudioArrival = nil
        lastAudioArrival = nil
        audioArrivalCount = 0
        stopFailure = nil
        writerURL = url
        if let movie {
            movie.maxRecordedDuration = CMTime(value: preparation.ticket.maximumDuration.ticks,
                                               timescale: preparation.ticket.maximumDuration.timescale)
            guard preparation.ticket.maximumFileBytes <= UInt64(Int64.max),
                  preparation.ticket.minimumRemainingBytes <= UInt64(Int64.max) else { throw ExplorationIssue.trialLimitsInvalid }
            movie.maxRecordedFileSize = Int64(preparation.ticket.maximumFileBytes)
            movie.minFreeDiskSpaceLimit = Int64(preparation.ticket.minimumRemainingBytes)
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
        let duration = preparation.ticket.maximumDuration.seconds
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
                if audioCount == sampleCount, let firstAudio {
                    audioSequence += 1
                    let span = CaptureSampleSpan(first: sampleTime(firstAudio, context: token.context),
                                                 last: sampleTime(latest, context: token.context), count: audioCount)
                    emit(.audioObserved(token.context, sequence: audioSequence, audioState(writing: .accepted(span))))
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
        guard let url = writerURL, let ticket = preparation?.ticket else { throw ExplorationIssue.ticketMissing }
        let resources = try url.resourceValues(forKeys: [.fileSizeKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let free = resources.volumeAvailableCapacityForImportantUsage, free >= 0 else {
            throw ExplorationIssue.capacityInsufficient
        }
        if UInt64(free) <= ticket.minimumRemainingBytes || UInt64(max(resources.fileSize ?? 0, 0)) >= ticket.maximumFileBytes {
            stopFailure = .resourceUnavailable
            stopRecording()
        }
    }

    fileprivate func sampleFailure(_ code: String, isAudio: Bool) {
        guard let token = activeToken, !isFinishing else { return }
        stopFailure = .adapterFailure(code: code)
        observe(code, context: token.context, time: ExplorationCaptureValues.now(), detail: "recording_stopped_no_retry")
        if isAudio {
            audioSequence += 1
            let failure = CaptureAudioFailure.writerFailed(.init(rawValue: "\(token.context.capture.rawValue)-\(code)"))
            emit(.audioObserved(token.context, sequence: audioSequence, audioState(writing: .failed(failure))))
        } else { emit(.commandFailed(token, .adapterFailure(code: code))) }
        stopRecording()
    }

    private func stopRecording() {
        guard activeToken != nil, !isFinishing else { return }
        isFinishing = true
        durationTask?.cancel()
        durationTask = nil
        if let movie, movie.isRecording {
            movie.stopRecording()
        } else if let writer {
            videoReceiver?.finish()
            audioReceiver?.finish()
            writer.finishWriting { [weak self] in
                Task { await self?.writerFinished() }
            }
        }
        // A stop during reserve() is completed by the start continuation, with no writer.
    }

    private func writerFinished() async {
        guard let writer, let token = activeToken else { return }
        let failure = writer.status == .completed ? stopFailure : .adapterFailure(code: "writer_finalize_failed")
        if writer.status == .completed, let firstAudio, let lastAudio {
            audioSequence += 1
            let span = CaptureSampleSpan(first: sampleTime(firstAudio, context: token.context),
                                         last: sampleTime(lastAudio, context: token.context), count: audioCount)
            emit(.audioObserved(token.context, sequence: audioSequence, audioState(writing: .completed(span))))
        }
        let evidence = RecordingEndEvidence(
            writer: failure.map(CaptureWriterTermination.interrupted) ?? .completed,
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
        let evidence = RecordingEndEvidence(writer: (failure ?? stopFailure).map(CaptureWriterTermination.interrupted) ?? .completed,
                                            ceasedAt: ExplorationCaptureValues.now(),
                                            lastVideo: .unavailable(.apiDoesNotExpose), lastAudio: .unavailable(.apiDoesNotExpose))
        await finish(token: token, evidence: evidence)
    }

    private func finish(token: CaptureCommandToken, evidence: RecordingEndEvidence) async {
        guard let intent = activeIntent else { return }
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
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            owner.assumeIsolated { $0.sampleFailure("sample_not_ready", isAudio: !isVideo) }
            return
        }
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
