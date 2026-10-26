import CoreVideo
import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureNDCompositionTests {
    @Test(arguments: [ExplorationOutputCandidate.sampleWriter, .movieFile])
    func productPolicyReachesAnalysisAndExpiresAfterOneSecondWithoutBlockingREC(candidate: ExplorationOutputCandidate) async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-capture-nd-policy-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        // Keep the isolated store until process teardown, matching the product-store
        // composition fixtures. No camera, network or frame-specific WB is simulated as verified.
        let services = try await ProductLibraryFactory(supportDirectory: parent).open()
        let fixture = try CaptureFixture()
        let underlying = ProductCaptureTestDevice(fixture: fixture)
        let device = NDCompositionDevice(underlying: underlying)
        let model = ProductCaptureFactory.make(services: services, didSave: {}, makeDevice: { selected, _, _, policy in
            #expect(selected == candidate)
            #expect(policy == ProductCaptureFactory.provisionalNDPolicyV1)
            #expect(policy.maximumResultAge == 1)
            #expect(policy.version == "s46-code-domain-reference-v1-uncalibrated")
            #expect(policy.isValid)
            await device.configureAnalysis(policy: policy)
            return device
        })
        model.enterCapture()
        await model.load()
        await model.updatePreferences(.init(desired: fixture.desired, outputCandidate: candidate, shootingIntent: .scenery))
        await model.prepare()
        try #require(model.canRecord)
        #expect(model.ndAdvice.direction == .pending)
        #expect(model.ndAdvice != .pending(.policyUnavailable))
        #expect(await device.policy == ProductCaptureFactory.provisionalNDPolicyV1)

        // The Factory-provided policy runs the real bounded ND analysis queue over
        // actual tagged BGRA pixels; the device fake only supplies capture control.
        let observedAt = try await device.emitPixels(base: 0.30)
        try #require(await eventually { model.ndAdvice.direction == .acceptable })
        #expect(model.ndSnapshot?.result?.observedAt == observedAt)
        #expect(model.ndSnapshot?.result?.evidence?.policyVersion == ProductCaptureFactory.provisionalNDPolicyV1.version)
        #expect(model.ndSnapshot?.result?.evidence?.signal == .rec709)
        #expect(model.ndSnapshot?.result?.evidence?.isCalibrated == false)
        #expect(ProcessInfo.processInfo.systemUptime - observedAt < 1)
        #expect(model.canRecord)
        #expect(await underlying.startCount == 0)

        // Refresh before the first frame expires. Its cancelled timer must not clear
        // the later frame, whose own deadline remains tied to its input timestamp.
        try await Task.sleep(for: .milliseconds(350))
        let latestObservedAt = try await device.emitPixels(base: 0.30)
        try #require(await eventually { model.ndSnapshot?.result?.observedAt == latestObservedAt })
        let latestReceivedAt = ProcessInfo.processInfo.systemUptime
        #expect(latestReceivedAt - latestObservedAt >= 0.25)
        let untilOldDeadline = observedAt + 1.05 - ProcessInfo.processInfo.systemUptime
        if untilOldDeadline > 0 { try await Task.sleep(for: .seconds(untilOldDeadline)) }
        #expect(model.ndSnapshot?.result?.observedAt == latestObservedAt)
        #expect(model.ndAdvice.direction == .acceptable)

        // No more frames arrive. The real coordinator timer clears the result one
        // second after input, not one second after the deliberately delayed delivery.
        try #require(await eventually { model.ndAdvice == .pending(.stale) })
        let expiredAt = ProcessInfo.processInfo.systemUptime
        #expect(expiredAt - latestObservedAt >= 1)
        #expect(expiredAt - latestReceivedAt < 1)
        #expect(model.ndSnapshot == nil)
        #expect(model.canRecord)
        await model.record()
        try #require(await eventually { model.capture?.phase == .recording })
        #expect(await underlying.startCount == 1)
        _ = try await device.emitPixels(base: 0.80)
        try #require(await eventually { model.ndAdvice.direction == .darker })
        #expect(model.capture?.phase == .recording)
        #expect(model.preferences.desired == fixture.desired)
        await device.endAnalysis()
        try #require(await eventually { model.ndAdvice == .pending(.stopped) })
        #expect(model.capture?.phase == .recording)
        await model.stop()
        try #require(await eventually { !model.isBusy })
        await model.leaveCapture()
        #expect(model.ndSnapshot == nil)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
        }
        return condition()
    }
}

private actor NDCompositionDevice: ProductCaptureDevicePort {
    let underlying: ProductCaptureTestDevice
    private(set) var policy: CaptureNDPolicy?
    private var generation: CaptureGeneration?
    private var intent: CaptureShootingIntent?
    private var analysis: NativeCaptureNDAnalysis?
    private let pair = AsyncStream<CaptureNDSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))

    init(underlying: ProductCaptureTestDevice) { self.underlying = underlying }
    func configureAnalysis(policy: CaptureNDPolicy) {
        self.policy = policy
        analysis?.stop()
        analysis = NativeCaptureNDAnalysis(policy: policy) { [weak self] result in
            Task { await self?.receive(result) }
        }
    }
    func events() async -> AsyncStream<CaptureIOEvent> { await underlying.events() }
    func productEvents() async -> AsyncStream<ExplorationDeviceEvent> { await underlying.productEvents() }
    func discoverCameras() async throws -> [ExplorationCameraDescription] { await underlying.discoverCameras() }
    func prepare(_ request: ProductCapturePreparation) async throws -> ExplorationPrepared {
        generation = request.generation
        return try await underlying.prepare(request)
    }
    func previewSource() async -> (any ProductCapturePreviewSource)? { await underlying.previewSource() }
    func submit(_ command: CaptureIOCommand) async -> CaptureCommandAcceptance { await underlying.submit(command) }
    func shutDown() async { endAnalysis(); await underlying.shutDown() }
    func ndSnapshots() -> AsyncStream<CaptureNDSnapshot> { pair.stream }
    func updateNDIntent(_ intent: CaptureShootingIntent?, generation: CaptureGeneration) {
        if self.generation == generation { self.intent = intent }
    }
    func endAnalysis() { analysis?.stop(); analysis = nil; pair.continuation.finish() }
    func emitPixels(base: Double) throws -> TimeInterval {
        let currentGeneration = self.generation
        let currentAnalysis = self.analysis
        let generation = try #require(currentGeneration)
        let analysis = try #require(currentAnalysis)
        let buffer = try NDCompositionPixels.make(base: base)
        let observedAt = ProcessInfo.processInfo.systemUptime
        let context = CaptureNDContext(generation: generation, framingRevision: 1,
            selectionRevision: 0, whiteBalanceRevision: 0, intent: intent)
        analysis.submit(buffer, instruction: .init(context: context, targets: [], targetsAvailable: true), observedAt: observedAt)
        return observedAt
    }
    private func receive(_ result: CaptureNDResult) async {
        // Model analysis/delivery latency without a backend: the source timestamp
        // remains the actual fixture input time passed into the real analysis queue.
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        guard analysis != nil else { return }
        pair.continuation.yield(.init(context: result.context, sequence: result.sequence,
            result: result, advice: result.advice))
    }
}

nonisolated private enum NDCompositionPixels {
    static func make(base: Double) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &created)
        try #require(status == kCVReturnSuccess)
        let buffer = try #require(created)
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        try #require(CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytes = try #require(CVPixelBufferGetBaseAddress(buffer))
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<64 { for x in 0..<64 {
            let pixel = bytes.advanced(by: y * rowBytes + x * 4)
            let code = UInt8(((base + Double(x % 20) / 100) * 255).rounded())
            for channel in 0..<3 { pixel.storeBytes(of: code, toByteOffset: channel, as: UInt8.self) }
            pixel.storeBytes(of: UInt8(255), toByteOffset: 3, as: UInt8.self)
        } }
        return buffer
    }
}
