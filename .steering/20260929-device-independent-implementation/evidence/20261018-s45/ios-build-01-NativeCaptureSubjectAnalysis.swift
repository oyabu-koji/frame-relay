import AVFoundation
import Vision
import ImageIO

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

    func submit(_ buffer: CVPixelBuffer, observedAt: TimeInterval) {
        lock.lock()
        guard !stopped, let instruction, observedAt - lastSubmitted >= policy.minimumFrameInterval else { lock.unlock(); return }
        lastSubmitted = observedAt; sequence += 1
        pending = Input(buffer: buffer, instruction: instruction, sequence: sequence, observedAt: observedAt)
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
                    return try engine.process(input.buffer, instruction: input.instruction,
                        sequence: input.sequence, observedAt: input.observedAt)
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
        let continuity: CapturePersonContinuity
    }
    private struct Anchor {
        let id: CapturePersonID
        let feature: VNFeaturePrintObservation
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
        if next.protagonist != instruction?.protagonist {
            anchor = next.protagonist.flatMap { id in
                people.first(where: { $0.id == id }).map {
                    Anchor(id: id, feature: $0.feature, observation: VNDetectedObjectObservation(boundingBox: $0.bounds))
                }
            }
            sequenceHandler = VNSequenceRequestHandler()
        }
        if !next.allowsReacquisition { anchor = nil }
        instruction = next
        let detection = VNDetectHumanRectanglesRequest()
        detection.upperBodyOnly = true
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        try handler.perform([detection])
        let observations = Array((detection.results ?? []).filter { $0.confidence >= policy.detectionConfidence }
            .sorted { $0.confidence > $1.confidence }.prefix(policy.maximumPeople))
        var detected: [(CGRect, VNFeaturePrintObservation)] = []
        for observation in observations {
            let feature = VNGenerateImageFeaturePrintRequest()
            feature.revision = VNGenerateImageFeaturePrintRequestRevision2
            let bounds = observation.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !bounds.isNull, !bounds.isEmpty, [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else { continue }
            feature.regionOfInterest = bounds
            feature.imageCropAndScaleOption = .scaleFit
            try handler.perform([feature])
            guard let value = feature.results?.first else { continue }
            detected.append((bounds, value))
        }

        var selectedIndex: Int?
        var selectedContinuity = CapturePersonContinuity.continuous
        if var selected = anchor {
            let tracking = VNTrackObjectRequest(detectedObjectObservation: selected.observation)
            tracking.trackingLevel = .accurate
            try sequenceHandler.perform([tracking], on: buffer, orientation: .up)
            let tracked = tracking.results?.first
            let distances = try detected.map { try Self.distance(selected.feature, $0.1) }
            let ranked = distances.indices.sorted { distances[$0] < distances[$1] }
            if let best = ranked.first {
                let continuous = selected.missingSince == nil && tracked.map {
                    $0.confidence >= policy.trackingConfidence && Self.overlap($0.boundingBox, detected[best].0) >= 0.25
                } == true
                let limit = continuous ? policy.continuousDistance : policy.reacquisitionDistance
                let unique = ranked.dropFirst().first.map { distances[$0] - distances[best] >= policy.ambiguityMargin } ?? true
                let withinGrace = selected.missingSince.map { observedAt - $0 <= policy.lostGrace } ?? true
                if unique && withinGrace && distances[best] <= limit {
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
                current.append(Person(id: anchor.id, bounds: detection.0, feature: detection.1, continuity: selectedContinuity))
                continue
            }
            // Other candidate IDs require both spatial continuity and unique appearance match.
            // They can never acquire the selected ID through this generic association path.
            var matches: [(Person, Float)] = []
            for previous in people where previous.id != next.protagonist && !used.contains(previous.id)
                && Self.overlap(previous.bounds, detection.0) >= 0.25 {
                let distance = try Self.distance(previous.feature, detection.1)
                if distance <= policy.continuousDistance { matches.append((previous, distance)) }
            }
            matches.sort { $0.1 < $1.1 }
            let match = matches.first.flatMap { first in
                matches.count == 1 || matches[1].1 - first.1 >= policy.ambiguityMargin ? first.0 : nil
            }
            let id = match?.id ?? CapturePersonID()
            used.insert(id)
            current.append(Person(id: id, bounds: detection.0, feature: detection.1,
                                  continuity: match == nil ? .newDetection : .continuous))
        }
        people = current
        return .init(context: next.context, sequence: sequence, observedAt: observedAt, candidates: current.map {
            .init(id: $0.id, bounds: .init(x: $0.bounds.minX, y: 1 - $0.bounds.maxY,
                width: $0.bounds.width, height: $0.bounds.height), continuity: $0.continuity)
        }, available: true)
    }

    static func distance(_ first: VNFeaturePrintObservation, _ second: VNFeaturePrintObservation) throws -> Float {
        var result: Float = 0
        try first.computeDistance(&result, to: second)
        return result
    }

    private static func overlap(_ first: CGRect, _ second: CGRect) -> Double {
        let area = first.intersection(second)
        guard !area.isNull else { return 0 }
        let intersection = area.width * area.height
        return intersection / (first.width * first.height + second.width * second.height - intersection)
    }
}
