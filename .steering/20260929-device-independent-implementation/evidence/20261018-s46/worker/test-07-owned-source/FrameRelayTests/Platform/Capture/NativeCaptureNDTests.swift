import CoreVideo
import Foundation
import Testing
@testable import FrameRelay

struct NativeCaptureNDTests {
    private let policy = CaptureNDPolicy.provisionalV1(maximumResultAge: 1)
    private func context(intent: CaptureShootingIntent? = .scenery, wb: UInt64 = 0, framing: UInt64 = 1, selection: UInt64 = 0) -> CaptureNDContext {
        .init(generation: .init(session: .init(rawValue: "nd-test"), settings: 1), framingRevision: framing,
              selectionRevision: selection, whiteBalanceRevision: wb, intent: intent)
    }
    private func evaluate(_ buffer: CVPixelBuffer, intent: CaptureShootingIntent? = .scenery,
                          targets: [NativeCaptureNDTarget] = [], available: Bool = true) -> CaptureNDResult {
        NativeCaptureNDPixels.evaluate(buffer, instruction: .init(context: context(intent: intent), targets: targets,
            targetsAvailable: available), policy: policy, sequence: 1, observedAt: 10)
    }

    @Test(arguments: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange])
    func actualPixelFormatsProduceDirectionsWithKnownSignal(format: OSType) throws {
        for (range, expected) in [(0.05...0.15, CaptureNDDirection.lighter), (0.3...0.6, .acceptable), (0.80...0.94, .darker)] {
            let buffer = try pixels(format: format) { x, _ in range.lowerBound + Double(x % 24) / 23 * (range.upperBound - range.lowerBound) }
            let result = evaluate(buffer)
            #expect(result.advice.direction == expected)
            #expect(result.evidence?.signal == .rec709)
            #expect(result.evidence?.isCalibrated == false)
            #expect(result.evidence?.policyVersion == policy.version)
        }
    }

    @Test(arguments: [CaptureNDSignal.appleLog, .appleLog2, .sRGB])
    func actualTaggedSignalsUseOwnProfile(signal: CaptureNDSignal) throws {
        let buffer = try pixels(format: signal == .sRGB ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            signal: signal) { x, _ in 0.80 + Double(x % 20) / 100 }
        let result = evaluate(buffer)
        #expect(result.evidence?.signal == signal)
        #expect(result.advice.direction == .darker)
    }

    @Test func unknownOrContradictoryTagsDoNotBorrowRecordingWish() throws {
        let buffer = try pixels { x, _ in 0.3 + Double(x % 20) / 100 }
        CVBufferRemoveAttachment(buffer, kCVImageBufferTransferFunctionKey)
        #expect(evaluate(buffer).advice == .pending(.unknownSignal))
        let log2 = try pixels(format: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, signal: .appleLog2) { x, _ in 0.3 + Double(x % 20) / 100 }
        CVBufferSetAttachment(log2, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
        #expect(evaluate(log2).advice == .pending(.unknownSignal))
        let yuv = try pixels(format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) { x, _ in 0.3 + Double(x % 20) / 100 }
        CVBufferRemoveAttachment(yuv, kCVImageBufferYCbCrMatrixKey)
        #expect(evaluate(yuv).advice == .pending(.unknownSignal))
    }

    @Test func smallSunReflectionAndBlackClothesDoNotDetermineDirection() throws {
        let buffer = try pixels { x, y in
            if x < 4 && y < 4 { return 1 }
            if x > 58 && y > 55 { return 0 }
            return 0.3 + Double(x % 20) / 100
        }
        #expect(evaluate(buffer).advice.direction == .acceptable)
        let broadBlack = try pixels { x, _ in x < 42 ? 0 : 0.3 + Double(x % 20) / 100 }
        #expect(evaluate(broadBlack).advice == .pending(.insufficientSignal))
        for code in [0.0, 0.4, 1.0] {
            #expect(try evaluate(pixels { _, _ in code }).advice.direction == .pending)
        }
    }

    @Test func selectedPeopleAndExcludedBackgroundAreEvaluatedIndependently() throws {
        let person = CapturePersonID()
        let target = NativeCaptureNDTarget(person: person, bounds: .init(x: 0, y: 0, width: 0.5, height: 1))
        let buffer = try pixels { x, _ in x < 32 ? 0.05 + Double(x % 12) / 100 : 0.8 + Double(x % 12) / 100 }
        let result = evaluate(buffer, intent: .peopleAndBackground, targets: [target])
        #expect(result.advice.direction == .difficult)
        #expect(result.advice.reasons == [.peopleAndBackgroundConflict])
        #expect(result.evidence?.people.first?.person == person)
        #expect((result.evidence?.people.first?.median ?? 1) < 0.2)
        #expect((result.evidence?.background?.median ?? 0) > 0.75)
    }

    @Test func multiplePeopleHaveNoSilentDropOrAverage() throws {
        let first = NativeCaptureNDTarget(person: .init(), bounds: .init(x: 0, y: 0, width: 0.5, height: 1))
        let second = NativeCaptureNDTarget(person: .init(), bounds: .init(x: 0.5, y: 0, width: 0.5, height: 1))
        let buffer = try pixels { x, _ in x < 32 ? 0.06 + Double(x % 10) / 100 : 0.81 + Double(x % 10) / 100 }
        #expect(evaluate(buffer, intent: .people, targets: [first, second]).advice.reasons == [.conflictingPeople])
        #expect(evaluate(buffer, intent: .people, targets: [first], available: false).advice == .pending(.missingPeople))
        let obscure = try pixels { x, _ in x < 32 ? 0.3 + Double(x % 10) / 100 : 0 }
        #expect(evaluate(obscure, intent: .people, targets: [first, second]).advice == .pending(.insufficientSignal))
        #expect(evaluate(buffer, intent: .people).advice == .pending(.selectPeople))
        #expect(evaluate(buffer, intent: nil).advice == .pending(.selectIntent))
    }

    @Test func geometryReversesMetadataCropAndRejectsPartiallyMissingPerson() throws {
        let geometry = NativeCaptureSubjectGeometry(outputAreaInMetadata: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.6))
        let raw = CaptureSubjectRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let metadata = try #require(geometry.metadataBounds(fromNormalizedOutput: raw))
        let recovered = try #require(geometry.normalizedOutputBounds(fromMetadata: metadata))
        #expect(abs(recovered.x - raw.x) < 0.000001)
        #expect(abs(recovered.height - raw.height) < 0.000001)
        #expect(geometry.normalizedOutputBounds(fromMetadata: .init(x: 0, y: 0, width: 0.4, height: 0.4)) == nil)
    }

    @Test func pixelResultExpiresAndOldOrderCannotRestoreOK() throws {
        let buffer = try pixels { x, _ in 0.3 + Double(x % 20) / 100 }
        let result = evaluate(buffer)
        var session = CaptureNDSession(context: context(), policy: policy)
        let accepted = session.receive(result, now: 10.1)
        #expect(accepted)
        #expect(session.advice.direction == .acceptable)
        let expired = session.expire(now: 11.01)
        #expect(expired)
        #expect(session.advice == .pending(.stale))
        let oldAccepted = session.receive(result, now: 11.1)
        #expect(!oldAccepted)
        #expect(session.advice == .pending(.outOfOrder))
        for changed in [context(wb: 1), context(framing: 2), context(selection: 1), context(intent: .people)] {
            session.update(changed)
            let obsoleteAccepted = session.receive(result, now: 10.2)
            #expect(!obsoleteAccepted)
            #expect(session.advice.direction == .pending)
        }
    }

    @Test func unavailableInputFencesAlreadyRunningResultBeforeItCanRestoreOK() throws {
        let buffer = try pixels { x, _ in 0.3 + Double(x % 20) / 100 }
        let running = evaluate(buffer)
        for reason in [CaptureNDReason.missingPeople, .stopped, .insufficientSignal] {
            var session = CaptureNDSession(context: context(), policy: policy)
            session.invalidateInput(reason)
            let accepted = session.receive(running, now: 10.1)
            #expect(!accepted)
            #expect(session.advice == .pending(reason))
            #expect(session.context.analysisRevision == 1)
            session.willSubmitInput()
            let recoveryInFlight = NativeCaptureNDPixels.evaluate(buffer, instruction: .init(context: session.context, targets: [], targetsAvailable: true),
                policy: policy, sequence: 2, observedAt: 10.2)
            session.invalidateInput(reason)
            let recoveryAccepted = session.receive(recoveryInFlight, now: 10.3)
            #expect(!recoveryAccepted)
            #expect(session.context.analysisRevision == 2)
            let fresh = NativeCaptureNDPixels.evaluate(buffer, instruction: .init(context: session.context, targets: [], targetsAvailable: true),
                policy: policy, sequence: 3, observedAt: 10.2)
            let freshAccepted = session.receive(fresh, now: 10.3)
            #expect(freshAccepted && session.advice.direction == .acceptable)
        }
    }

    @Test func invalidPolicyIsRejectedBeforePixelEvaluation() throws {
        let invalid = CaptureNDPolicy(version: "bad", maximumResultAge: .nan, minimumFrameInterval: 0.2,
            maximumSubjectAge: 1, bands: policy.bands)
        #expect(!invalid.isValid)
        let buffer = try pixels { x, _ in 0.3 + Double(x % 20) / 100 }
        let result = NativeCaptureNDPixels.evaluate(buffer, instruction: .init(context: context(), targets: [], targetsAvailable: true),
            policy: invalid, sequence: 1, observedAt: 10)
        #expect(result.advice == .pending(.policyUnavailable))
    }

    @Test func realBufferRunsThroughAsyncAnalysisAndStopReleasesPendingInputs() async throws {
        let results = AsyncStream<CaptureNDResult>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let analysis = NativeCaptureNDAnalysis(policy: policy) { results.continuation.yield($0) }
        let buffer = try pixels { x, _ in 0.8 + Double(x % 12) / 100 }
        analysis.submit(buffer, instruction: .init(context: context(), targets: [], targetsAvailable: true), observedAt: .infinity)
        analysis.submit(buffer, instruction: .init(context: context(), targets: [], targetsAvailable: true), observedAt: .nan)
        analysis.submit(buffer, instruction: .init(context: context(), targets: [], targetsAvailable: true), observedAt: 10)
        var iterator = results.stream.makeAsyncIterator()
        let result = try #require(await iterator.next())
        #expect(result.advice.direction == .darker)
        var session = CaptureNDSession(context: context(), policy: policy)
        let accepted = session.receive(result, now: 10.1)
        #expect(accepted)
        analysis.stop()
        session.invalidate(.stopped)
        #expect(session.result == nil && session.advice == .pending(.stopped))
        analysis.submit(buffer, instruction: .init(context: context(), targets: [], targetsAvailable: true), observedAt: 11)
        results.continuation.finish()
        let afterStop = await iterator.next()
        #expect(afterStop == nil)
    }

    private func pixels(format: OSType = kCVPixelFormatType_32BGRA, signal: CaptureNDSignal = .rec709,
                        value: (Int, Int) -> Double) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, format,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &created) == kCVReturnSuccess)
        let buffer = try #require(created)
        if signal == .appleLog || signal == .appleLog2 {
            CVBufferSetAttachment(buffer, kCVImageBufferLogTransferFunctionKey,
                signal == .appleLog ? kCVImageBufferLogTransferFunction_AppleLog : kCVImageBufferLogTransferFunction_AppleLog2, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
            if signal == .appleLog { CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate) }
        } else {
            CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey,
                signal == .sRGB ? kCVImageBufferTransferFunction_sRGB : kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
            if format != kCVPixelFormatType_32BGRA { CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate) }
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bgra = format == kCVPixelFormatType_32BGRA
        let ten = format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
        let video = format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let base = try #require(bgra ? CVPixelBufferGetBaseAddress(buffer) : CVPixelBufferGetBaseAddressOfPlane(buffer, 0))
        let rowBytes = bgra ? CVPixelBufferGetBytesPerRow(buffer) : CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for y in 0..<64 { for x in 0..<64 {
            let v = min(1, max(0, value(x, y)))
            if bgra {
                let pixel = base.advanced(by: y * rowBytes + x * 4)
                for channel in 0..<3 { pixel.storeBytes(of: UInt8((v * 255).rounded()), toByteOffset: channel, as: UInt8.self) }
                pixel.storeBytes(of: UInt8(255), toByteOffset: 3, as: UInt8.self)
            } else if ten {
                let code = UInt16(((video ? 64 : 0) + v * (video ? 876 : 1023)).rounded()) << 6
                base.storeBytes(of: code, toByteOffset: y * rowBytes + x * 2, as: UInt16.self)
            } else {
                base.storeBytes(of: UInt8(((video ? 16 : 0) + v * (video ? 219 : 255)).rounded()), toByteOffset: y * rowBytes + x, as: UInt8.self)
            }
        } }
        return buffer
    }
}
