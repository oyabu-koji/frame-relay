import AVFoundation
import Vision
import CoreML
import ImageIO
import CryptoKit

nonisolated struct NativeSubjectAnalysisInstruction: Equatable, Sendable {
    let context: CaptureSubjectContext
    let protagonist: CapturePersonID?
    let allowsReacquisition: Bool
}

/// A single in-flight buffer and a single replaceable pending buffer. SDK sample queues
/// only retain/replace references; all Vision requests execute on the utility queue.
nonisolated final class NativeCaptureSubjectAnalysis: @unchecked Sendable {
    private struct Input {
        let buffer: CVPixelBuffer
        let geometry: NativeCaptureSubjectGeometry
        let instruction: NativeSubjectAnalysisInstruction
        let sequence: UInt64
        let observedAt: TimeInterval
    }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "FrameRelay.SubjectAnalysis", qos: .utility)
    private let engine: NativeSubjectVisionEngine
    private let policy: CaptureSubjectPolicy
    private let output: @Sendable (CaptureSubjectAnalysis) -> Void
    private var instruction: NativeSubjectAnalysisInstruction?
    private var pending: Input?
    private var running = false
    private var stopped = false
    private var sequence: UInt64 = 0
    private var lastSubmitted: TimeInterval = -.infinity

    init(policy: CaptureSubjectPolicy, output: @escaping @Sendable (CaptureSubjectAnalysis) -> Void) {
        self.policy = policy; self.output = output; engine = NativeSubjectVisionEngine(policy: policy)
    }

    func configure(_ value: NativeSubjectAnalysisInstruction) {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        instruction = value
        // The running result carries its old context and is rejected by the SDK owner.
        pending = nil
    }

    func submit(_ buffer: CVPixelBuffer, geometry: NativeCaptureSubjectGeometry, observedAt: TimeInterval) {
        lock.lock()
        guard !stopped, let instruction, observedAt - lastSubmitted >= policy.minimumFrameInterval else { lock.unlock(); return }
        lastSubmitted = observedAt; sequence += 1
        pending = Input(buffer: buffer, geometry: geometry, instruction: instruction, sequence: sequence, observedAt: observedAt)
        let shouldStart = !running
        running = true
        lock.unlock()
        if shouldStart { queue.async { [self] in drain() } }
    }

    func stop() {
        lock.lock(); stopped = true; pending = nil; instruction = nil; lock.unlock()
        // FIFO disposal releases all feature observations after the in-flight request.
        queue.async { [self] in engine.reset() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard !stopped, let input = pending else { running = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            let result: CaptureSubjectAnalysis = autoreleasepool {
                do {
                    let raw = try engine.process(input.buffer, instruction: input.instruction,
                        sequence: input.sequence, observedAt: input.observedAt)
                    return input.geometry.map(raw)
                } catch {
                    return .init(context: input.instruction.context, sequence: input.sequence,
                                 observedAt: input.observedAt, candidates: [], available: false)
                }
            }
            lock.lock()
            let current = !stopped && instruction?.context == result.context
            lock.unlock()
            if current { output(result) }
        }
    }
}

/// Queue-confined Vision implementation. UUIDs emitted by Vision are never used as identity.
/// The selected reference is fixed at the explicit selection; it is never replaced with a
/// nearby person's crop. Conservative image matching still needs DV-06 identity/AF evaluation.
nonisolated final class NativeSubjectVisionEngine {
    private struct Person {
        let id: CapturePersonID
        let bounds: CGRect // Vision normalized lower-left coordinates
        let feature: VNFeaturePrintObservation
        let collisionFeature: VNFeaturePrintObservation
        let pixels: NativeSubjectImageFingerprint
        let continuity: CapturePersonContinuity
    }
    private struct Anchor {
        let id: CapturePersonID
        let feature: VNFeaturePrintObservation
        let collisionFeature: VNFeaturePrintObservation
        let pixels: NativeSubjectImageFingerprint
        var observation: VNDetectedObjectObservation
        var missingSince: TimeInterval?
    }
    private let policy: CaptureSubjectPolicy
    private var instruction: NativeSubjectAnalysisInstruction?
    private var people: [Person] = []
    private var anchor: Anchor?
    private var sequenceHandler = VNSequenceRequestHandler()

    init(policy: CaptureSubjectPolicy) { self.policy = policy }

    func reset() {
        instruction = nil; people = []; anchor = nil; sequenceHandler = VNSequenceRequestHandler()
    }

    func process(_ buffer: CVPixelBuffer, instruction next: NativeSubjectAnalysisInstruction,
                 sequence: UInt64, observedAt: TimeInterval) throws -> CaptureSubjectAnalysis {
        if instruction?.context.generation != next.context.generation || instruction?.context.framingRevision != next.context.framingRevision {
            reset()
        }
        if next.protagonist != instruction?.protagonist || (next.allowsReacquisition && instruction?.allowsReacquisition == false) {
            anchor = next.protagonist.flatMap { id in
                people.first(where: { $0.id == id }).map {
                    Anchor(id: id, feature: $0.feature, collisionFeature: $0.collisionFeature, pixels: $0.pixels, observation: VNDetectedObjectObservation(boundingBox: $0.bounds))
                }
            }
            sequenceHandler = VNSequenceRequestHandler()
        }
        if !next.allowsReacquisition { anchor = nil }
        instruction = next
        let detection = VNDetectHumanRectanglesRequest()
        detection.upperBodyOnly = true
        try configureCompute(detection)
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        try handler.perform([detection])
        guard let detectionResults = detection.results else { throw NativeSubjectVisionError.missingDetectionEvidence }
        let observations = Array(detectionResults.filter { $0.confidence >= policy.detectionConfidence }
            .sorted { $0.confidence > $1.confidence }.prefix(policy.maximumPeople))
        var detected: [(CGRect, VNFeaturePrintObservation, VNFeaturePrintObservation, NativeSubjectImageFingerprint)] = []
        for observation in observations {
            let bounds = observation.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !bounds.isNull, !bounds.isEmpty, [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else {
                throw NativeSubjectVisionError.invalidDetection
            }
            let value = try featurePrint(handler: handler, bounds: bounds)
            // Bound reference preparation to two real requests over the same immutable
            // crop. The second output only vetoes collisions; it never relaxes distance.
            // Preparing it now also protects a selection followed immediately by another
            // person, before any continuous frame of the selected person can arrive.
            let confirmation = try featurePrint(handler: VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up), bounds: bounds)
            detected.append((bounds, value, confirmation, try NativeSubjectImageFingerprint(buffer: buffer, bounds: bounds)))
        }

        var selectedIndex: Int?
        var selectedContinuity = CapturePersonContinuity.continuous
        if var selected = anchor {
            let tracking = VNTrackObjectRequest(detectedObjectObservation: selected.observation)
            tracking.trackingLevel = .accurate
            try configureCompute(tracking)
            let tracked: VNDetectedObjectObservation?
            do {
                try sequenceHandler.perform([tracking], on: buffer, orientation: .up)
                tracked = tracking.results?.first as? VNDetectedObjectObservation
            } catch {
                // Tracking loss does not turn a valid fresh person detection into failure.
                // Reacquisition still requires the fixed reference and unique candidate margin.
                tracked = nil
                sequenceHandler = VNSequenceRequestHandler()
            }
            let distances = try detected.map { try Self.distance(selected.feature, $0.1) }
            let ranked = distances.indices.sorted { distances[$0] < distances[$1] }
            if let best = ranked.first {
                let continuous = selected.missingSince == nil && tracked.map {
                    $0.confidence >= policy.trackingConfidence && Self.overlap($0.boundingBox, detected[best].0) >= 0.25
                } == true
                let limit = continuous ? policy.continuousDistance : policy.reacquisitionDistance
                let unique = ranked.dropFirst().first.map { distances[$0] - distances[best] >= policy.ambiguityMargin } ?? true
                let withinGrace = selected.missingSince.map { observedAt - $0 <= policy.lostGrace } ?? true
                // A feature extractor can return the exact same vector for different images.
                // Equal features alone cannot establish continuity in that case. Reject the
                // collision against the fixed reference; never replace it with this crop.
                let collision = Self.collides((selected.feature, selected.collisionFeature), pixels: selected.pixels,
                                              with: (detected[best].1, detected[best].2), pixels: detected[best].3)
                if !collision && unique && withinGrace && distances[best] <= limit {
                    selectedIndex = best
                    selectedContinuity = continuous ? .continuous : .reacquired
                    selected.observation = VNDetectedObjectObservation(boundingBox: detected[best].0)
                    selected.missingSince = nil
                }
            }
            if selectedIndex == nil && selected.missingSince == nil { selected.missingSince = observedAt }
            anchor = selected
        }

        var used: Set<CapturePersonID> = []
        var current: [Person] = []
        for (index, detection) in detected.enumerated() {
            if index == selectedIndex, let anchor {
                used.insert(anchor.id)
                current.append(Person(id: anchor.id, bounds: detection.0, feature: detection.1, collisionFeature: detection.2, pixels: detection.3, continuity: selectedContinuity))
                continue
            }
            // Other candidate IDs require both spatial continuity and unique appearance match.
            // They can never acquire the selected ID through this generic association path.
            var matches: [(Person, Float)] = []
            for previous in people where previous.id != next.protagonist && !used.contains(previous.id)
                && Self.overlap(previous.bounds, detection.0) >= 0.25 {
                let distance = try Self.distance(previous.feature, detection.1)
                if distance <= policy.continuousDistance
                    && !Self.collides((previous.feature, previous.collisionFeature), pixels: previous.pixels,
                                      with: (detection.1, detection.2), pixels: detection.3) {
                    var ambiguous = false
                    for (otherIndex, other) in detected.enumerated() where otherIndex != index
                        && Self.overlap(previous.bounds, other.0) >= 0.25 {
                        if try Self.distance(previous.feature, other.1) - distance < policy.ambiguityMargin { ambiguous = true; break }
                    }
                    if !ambiguous { matches.append((previous, distance)) }
                }
            }
            matches.sort { $0.1 < $1.1 }
            let match = matches.first.flatMap { first in
                matches.count == 1 || matches[1].1 - first.1 >= policy.ambiguityMargin ? first.0 : nil
            }
            let id = match?.id ?? CapturePersonID()
            used.insert(id)
            current.append(Person(id: id, bounds: detection.0, feature: detection.1, collisionFeature: detection.2, pixels: detection.3,
                                  continuity: match == nil ? .newDetection : .continuous))
        }
        people = current
        return .init(context: next.context, sequence: sequence, observedAt: observedAt, candidates: current.map {
            .init(id: $0.id, bounds: .init(x: $0.bounds.minX, y: 1 - $0.bounds.maxY,
                width: $0.bounds.width, height: $0.bounds.height), continuity: $0.continuity)
        }, available: detectionResults.isEmpty || !observations.isEmpty)
    }

    /// Simulator lacks the device inference hardware used by Vision's automatic
    /// selection. Use real CPU inference for every supported stage; never substitute
    /// observations, relax assertions, or infer device quality from this environment.
    private func configureCompute(_ request: VNRequest) throws {
        #if targetEnvironment(simulator)
        let stages = try request.supportedComputeStageDevices
        guard !stages.isEmpty else { throw NativeSubjectVisionError.cpuUnavailable }
        for (stage, devices) in stages {
            guard let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) else {
                throw NativeSubjectVisionError.cpuUnavailable
            }
            request.setComputeDevice(cpu, for: stage)
        }
        #endif
    }

    static func distance(_ first: VNFeaturePrintObservation, _ second: VNFeaturePrintObservation) throws -> Float {
        var result: Float = 0
        try first.computeDistance(&result, to: second)
        return result
    }

    private func featurePrint(handler: VNImageRequestHandler, bounds: CGRect) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.regionOfInterest = bounds
        request.imageCropAndScaleOption = .scaleFit
        try configureCompute(request)
        try handler.perform([request])
        guard let result = request.results?.first else { throw NativeSubjectVisionError.missingFeature }
        return result
    }

    private static func collides(_ first: (VNFeaturePrintObservation, VNFeaturePrintObservation), pixels firstPixels: NativeSubjectImageFingerprint,
                                 with second: (VNFeaturePrintObservation, VNFeaturePrintObservation), pixels secondPixels: NativeSubjectImageFingerprint) -> Bool {
        guard firstPixels != secondPixels else { return false }
        return first.0.data == second.0.data || first.0.data == second.1.data
            || first.1.data == second.0.data || first.1.data == second.1.data
    }

    private static func overlap(_ first: CGRect, _ second: CGRect) -> Double {
        let area = first.intersection(second)
        guard !area.isNull else { return 0 }
        let intersection = area.width * area.height
        return intersection / (first.width * first.height + second.width * second.height - intersection)
    }
}

nonisolated private enum NativeSubjectVisionError: Error {
    case cpuUnavailable, missingDetectionEvidence, invalidDetection, missingFeature, invalidPixelBuffer
}

/// An exact, ephemeral digest of the detected crop, independent of Vision's feature
/// extraction. This is a collision veto, never an alternative identity score. Different
/// crops with identical features remain unconfirmed even if they depict the same person.
/// Raw pixels and digests never leave the analysis queue or survive its session.
nonisolated struct NativeSubjectImageFingerprint: Equatable {
    private struct Plane: Equatable {
        let width: Int
        let height: Int
        let digest: SHA256.Digest
    }
    private let format: OSType
    private let planes: [Plane]

    init(buffer: CVPixelBuffer, bounds: CGRect) throws {
        guard !bounds.isNull, !bounds.isEmpty,
              [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].allSatisfy(\.isFinite),
              bounds.minX >= 0, bounds.minY >= 0, bounds.maxX <= 1, bounds.maxY <= 1 else {
            throw NativeSubjectVisionError.invalidDetection
        }
        format = CVPixelBufferGetPixelFormatType(buffer)
        let bytesPerPixel: [Int]
        switch format {
        case kCVPixelFormatType_32BGRA: bytesPerPixel = [4]
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            bytesPerPixel = [1, 2]
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            bytesPerPixel = [2, 4]
        default: throw NativeSubjectVisionError.invalidPixelBuffer
        }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            throw NativeSubjectVisionError.invalidPixelBuffer
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(buffer)
        guard planar ? CVPixelBufferGetPlaneCount(buffer) == bytesPerPixel.count : bytesPerPixel.count == 1 else {
            throw NativeSubjectVisionError.invalidPixelBuffer
        }
        var result: [Plane] = []
        for (index, pixelBytes) in bytesPerPixel.enumerated() {
            let width = planar ? CVPixelBufferGetWidthOfPlane(buffer, index) : CVPixelBufferGetWidth(buffer)
            let height = planar ? CVPixelBufferGetHeightOfPlane(buffer, index) : CVPixelBufferGetHeight(buffer)
            let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, index) : CVPixelBufferGetBytesPerRow(buffer)
            let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, index) : CVPixelBufferGetBaseAddress(buffer)
            guard let base, rowBytes >= width * pixelBytes else { throw NativeSubjectVisionError.invalidPixelBuffer }
            let left = max(0, Int(floor(bounds.minX * Double(width))))
            let right = min(width, Int(ceil(bounds.maxX * Double(width))))
            let top = max(0, Int(floor((1 - bounds.maxY) * Double(height))))
            let bottom = min(height, Int(ceil((1 - bounds.minY) * Double(height))))
            guard left < right, top < bottom else { throw NativeSubjectVisionError.invalidPixelBuffer }
            var hash = SHA256()
            for row in top..<bottom {
                hash.update(bufferPointer: UnsafeRawBufferPointer(start: base.advanced(by: row * rowBytes + left * pixelBytes),
                                                                  count: (right - left) * pixelBytes))
            }
            result.append(Plane(width: right - left, height: bottom - top, digest: hash.finalize()))
        }
        planes = result
    }
}
