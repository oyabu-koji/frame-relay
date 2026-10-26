import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import Testing
@testable import FrameRelay

struct CaptureDisplayTests {
    private func context(_ settings: UInt64 = 1, revision: UInt64 = 1) -> CaptureDisplayContext {
        .init(generation: .init(session: .init(rawValue: "display-fixture"), settings: settings), displayRevision: revision)
    }

    @Test(arguments: [CaptureLogEncoding.appleLog, .appleLog2])
    func emptyProductCatalogRefusesEachLogIndependently(encoding: CaptureLogEncoding) {
        #expect(throws: CaptureDisplayError.standardAssetUnavailable(encoding)) {
            try CaptureDisplayTransformCatalog().standardTransform(for: encoding)
        }
    }

    @Test(arguments: [CaptureNDSignal.sRGB, .rec709])
    func actualRasterMatchesGeneratedCubeAndPreservesAllInputBytesAndAttachments(signal: CaptureNDSignal) throws {
        for swap in [false, true] {
            let buffer = try pixels(signal: signal)
            let before = try pixelBytes(buffer)
            let propagating = try #require(CVBufferCopyAttachments(buffer, .shouldPropagate))
            let privateTags = try #require(CVBufferCopyAttachments(buffer, .shouldNotPropagate))
            let transform = try fixture(swap: swap, signal: signal)
            let frame = try CaptureDisplayRenderer().render(buffer, origin: .captureOriginal, context: context(),
                                                            sequence: 7, transform: transform)
            #expect(frame.use == .technicalFixture)
            #expect(frame.context == context() && frame.sequence == 7)
            #expect(frame.transformID == transform.identifier && frame.transformVersion == transform.version)
            #expect(frame.transformSHA256 == transform.sha256)
            #expect(frame.image.width == 4 && frame.image.height == 2)
            #expect(try pixelBytes(buffer) == before)
            let afterPropagating = try #require(CVBufferCopyAttachments(buffer, .shouldPropagate))
            let afterPrivateTags = try #require(CVBufferCopyAttachments(buffer, .shouldNotPropagate))
            #expect(CFEqual(propagating, afterPropagating))
            #expect(CFEqual(privateTags, afterPrivateTags))

            let output = try rgba(frame.image)
            for y in 0..<2 {
                for x in 0..<4 {
                    let source = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                    let destination = y * frame.image.bytesPerRow + x * 4
                    let expectedR = Int(before[source + (swap ? 0 : 2)])
                    let expectedB = Int(before[source + (swap ? 2 : 0)])
                    #expect(abs(Int(output[destination]) - expectedR) <= 1)
                    #expect(abs(Int(output[destination + 1]) - Int(before[source + 1])) <= 1)
                    #expect(abs(Int(output[destination + 2]) - expectedB) <= 1)
                    #expect(output[destination + 3] == 255)
                    if swap { #expect(abs(Int(output[destination]) - Int(before[source + 2])) > 50) }
                }
            }
            // Immediate rasterization must detach the image from its input buffer.
            try clear(buffer)
            #expect(try rgba(frame.image) == output)
        }
    }

    @Test func changedUnknownAndLogSignalsCannotBorrowTheFixtureContract() throws {
        let transform = try fixture()
        let renderer = CaptureDisplayRenderer()
        let rec709 = try pixels(signal: .rec709)
        #expect(throws: CaptureDisplayError.signalMismatch) {
            try renderer.render(rec709, origin: .captureOriginal, context: context(), sequence: 1, transform: transform)
        }
        let unknown = try pixels()
        CVBufferRemoveAttachment(unknown, kCVImageBufferTransferFunctionKey)
        #expect(throws: CaptureDisplayError.signalMismatch) {
            try renderer.render(unknown, origin: .captureOriginal, context: context(), sequence: 1, transform: transform)
        }
        for log in [kCVImageBufferLogTransferFunction_AppleLog, kCVImageBufferLogTransferFunction_AppleLog2] {
            let tagged = try pixels()
            CVBufferSetAttachment(tagged, kCVImageBufferLogTransferFunctionKey, log, .shouldPropagate)
            #expect(throws: CaptureDisplayError.signalMismatch) {
                try renderer.render(tagged, origin: .captureOriginal, context: context(), sequence: 1, transform: transform)
            }
        }
        let wrongGamut = try pixels()
        CVBufferSetAttachment(wrongGamut, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
        #expect(throws: CaptureDisplayError.signalMismatch) {
            try renderer.render(wrongGamut, origin: .captureOriginal, context: context(), sequence: 1, transform: transform)
        }
    }

    @Test func convertedInputIsRefusedWithoutChangingItsAttachments() throws {
        let buffer = try pixels()
        let tags = try #require(CVBufferCopyAttachments(buffer, .shouldPropagate))
        let transform = try fixture()
        #expect(throws: CaptureDisplayError.alreadyConverted) {
            try CaptureDisplayRenderer().render(buffer, origin: .displayConverted, context: context(), sequence: 1, transform: transform)
        }
        let afterTags = try #require(CVBufferCopyAttachments(buffer, .shouldPropagate))
        #expect(CFEqual(tags, afterTags))
        let events = DisplayEvents()
        let pipeline = CaptureDisplayPipeline(context: context(), transform: transform, output: events.receive)
        #expect(pipeline.submit(buffer, origin: .displayConverted, context: context(), sequence: 1) == .alreadyConverted)
        pipeline.stop()
        #expect(events.sequences.isEmpty)
    }

    @Test func fixtureMustCarryProvenanceVersionExactHashAndFiniteNormalizedOpaqueValues() throws {
        let bytes = cube()
        for (version, source, usage) in [("", "generated-in-test", "technical-only"), ("v1", " ", "technical-only"), ("v1", "generated-in-test", "")] {
            #expect(throws: CaptureDisplayError.invalidFixture) {
                try CaptureDisplayTransform(technicalFixtureID: "test", version: version, source: source, usage: usage,
                    inputSignal: .sRGB, dimension: 2, rgbaCube: bytes, expectedSHA256: digest(bytes))
            }
        }
        #expect(throws: CaptureDisplayError.digestMismatch) {
            try CaptureDisplayTransform(technicalFixtureID: "test", version: "v1", source: "generated-in-test", usage: "technical-only",
                inputSignal: .sRGB, dimension: 2, rgbaCube: bytes, expectedSHA256: String(repeating: "0", count: 64))
        }
        for signal in [CaptureNDSignal.appleLog, .appleLog2] {
            #expect(throws: CaptureDisplayError.invalidFixture) { try fixture(signal: signal) }
        }
        for value in [Float.nan, .infinity, -0.1, 1.1] {
            var invalid = bytes
            withUnsafeBytes(of: value) { invalid.replaceSubrange(0..<4, with: $0) }
            #expect(throws: CaptureDisplayError.invalidFixture) { try fixture(bytes: invalid) }
        }
        var transparent = bytes
        withUnsafeBytes(of: Float(0)) { transparent.replaceSubrange(12..<16, with: $0) }
        #expect(throws: CaptureDisplayError.invalidFixture) { try fixture(bytes: transparent) }
        #expect(throws: CaptureDisplayError.invalidFixture) { try fixture(bytes: bytes.dropLast()) }
    }

    @Test func pendingInputIsReplacedAndSequenceHighWaterRejectsOldFrames() throws {
        let events = DisplayEvents()
        let gate = DisplayDrawGate()
        let buffer = try pixels()
        let pipeline = CaptureDisplayPipeline(context: context(), transform: try fixture(), draw: gate.draw, output: events.receive)
        defer { gate.release.signal(); pipeline.stop() }
        #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 1) == nil)
        try requireSignal(gate.entered)
        #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 2) == nil)
        #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 3) == nil)
        #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 2) == .outOfOrder)
        gate.release.signal()
        try requireSignal(events.published)
        try requireSignal(events.published)
        #expect(events.sequences == [1, 3])
        #expect(gate.sequences == [1, 3])
        #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 3) == .outOfOrder)
    }

    @Test(arguments: [false, true])
    func inFlightResultCannotReviveAfterContextRoundTripOrStopAndSameContextActivation(stop: Bool) throws {
        let events = DisplayEvents()
        let gate = DisplayDrawGate()
        let buffer = try pixels()
        let pipeline = CaptureDisplayPipeline(context: context(), transform: try fixture(), draw: gate.draw, output: events.receive)
        defer { gate.release.signal(); pipeline.stop() }
        #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 1) == nil)
        try requireSignal(gate.entered)
        if stop {
            pipeline.stop()
            #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 2) == .stopped)
        } else {
            pipeline.activate(context: context(2, revision: 2))
            #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 2) == .staleContext)
        }
        pipeline.activate(context: context())
        #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 2) == nil)
        gate.release.signal()
        try requireSignal(events.published)
        #expect(events.sequences == [2])
        pipeline.stop()
        #expect(pipeline.submit(buffer, origin: .captureOriginal, context: context(), sequence: 3) == .stopped)
    }

    private func fixture(swap: Bool = true, signal: CaptureNDSignal = .sRGB, bytes: Data? = nil) throws -> CaptureDisplayTransform {
        let bytes = bytes ?? cube(swap: swap)
        return try .init(technicalFixtureID: swap ? "generated-red-blue-swap" : "generated-identity", version: "test-v1",
            source: "generated-inside-CaptureDisplayTests", usage: "technical drawing only; no standard transform claim",
            inputSignal: signal, dimension: 2, rgbaCube: bytes, expectedSHA256: digest(bytes))
    }
    private func cube(swap: Bool = true) -> Data {
        var values: [Float] = []
        for b in [Float(0), 1] { for g in [Float(0), 1] { for r in [Float(0), 1] {
            values += swap ? [b, g, r, 1] : [r, g, b, 1]
        } } }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private func pixels(signal: CaptureNDSignal = .sRGB) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 4, 2, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result)
        #expect(status == kCVReturnSuccess)
        let buffer = try #require(result)
        #expect(CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let pointer = try #require(CVPixelBufferGetBaseAddress(buffer))
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        memset(pointer, 0, rowBytes * 2)
        for y in 0..<2 { for x in 0..<4 {
            let pixel = pointer.advanced(by: y * rowBytes + x * 4)
            pixel.storeBytes(of: UInt8(24 + 7 * x), as: UInt8.self)
            pixel.storeBytes(of: UInt8(60 + 9 * y), toByteOffset: 1, as: UInt8.self)
            pixel.storeBytes(of: UInt8(200 + 4 * x), toByteOffset: 2, as: UInt8.self)
            pixel.storeBytes(of: UInt8(255), toByteOffset: 3, as: UInt8.self)
        } }
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey,
            signal == .sRGB ? kCVImageBufferTransferFunction_sRGB : kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, "FrameRelay.fixture-note" as CFString, "retain-this-metadata" as CFString, .shouldNotPropagate)
        return buffer
    }
    private func pixelBytes(_ buffer: CVPixelBuffer) throws -> Data {
        #expect(CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let pointer = try #require(CVPixelBufferGetBaseAddress(buffer))
        return Data(bytes: pointer,
                    count: CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
    }
    private func clear(_ buffer: CVPixelBuffer) throws {
        #expect(CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let pointer = try #require(CVPixelBufferGetBaseAddress(buffer))
        memset(pointer, 0, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
    }
    private func rgba(_ image: CGImage) throws -> Data {
        #expect(image.bitsPerPixel == 32 && image.bitsPerComponent == 8)
        let provider = try #require(image.dataProvider)
        let data = try #require(provider.data)
        return data as Data
    }
    private func requireSignal(_ semaphore: DispatchSemaphore) throws {
        try #require(semaphore.wait(timeout: .now() + 5) == .success)
    }
}

/// Test-only coordination makes replacement and invalidation races deterministic.
private final class DisplayDrawGate: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var drawn: [UInt64] = []
    private let renderer = CaptureDisplayRenderer()
    var sequences: [UInt64] { lock.lock(); defer { lock.unlock() }; return drawn }
    func draw(_ buffer: CVPixelBuffer, _ origin: CaptureDisplayRenderer.InputOrigin, _ context: CaptureDisplayContext,
              _ sequence: UInt64, _ transform: CaptureDisplayTransform) throws -> CaptureDisplayFrame {
        lock.lock(); drawn.append(sequence); lock.unlock()
        if sequence == 1 {
            entered.signal()
            guard release.wait(timeout: .now() + 5) == .success else { throw CaptureDisplayError.renderFailed }
        }
        return try renderer.render(buffer, origin: origin, context: context, sequence: sequence, transform: transform)
    }
}
private final class DisplayEvents: @unchecked Sendable {
    let published = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var frames: [UInt64] = []
    var sequences: [UInt64] { lock.lock(); defer { lock.unlock() }; return frames }
    func receive(_ result: Result<CaptureDisplayFrame, CaptureDisplayError>) {
        lock.lock()
        if case .success(let frame) = result { frames.append(frame.sequence) }
        lock.unlock()
        published.signal()
    }
}
