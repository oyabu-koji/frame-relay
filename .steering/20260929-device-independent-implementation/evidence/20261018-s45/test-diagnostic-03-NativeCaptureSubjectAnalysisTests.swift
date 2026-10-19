import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import Testing
import Vision
import CoreML
import CryptoKit
@testable import FrameRelay

/// Real Vision requests over public NASA portraits. These assertions certify only
/// these input transformations, not person identity, live Log imagery or lens focus.
struct NativeCaptureSubjectAnalysisTests {
    @Test func realVisionDetectsTracksRejectsAnotherPersonAndReacquiresFixedReference() throws {
        let engine = NativeSubjectVisionEngine(policy: policy)
        let sally = try image("sally-ride-1979")
        let mae = try image("mae-jemison-1987")
        var instruction = instruction()
        let initial = try engine.process(buffer([sally]), instruction: instruction, sequence: 1, observedAt: 1)
        #expect(initial.available)
        let selected = try #require(initial.candidates.first)
        #expect(selected.bounds.isValid)
        instruction = .init(context: .init(generation: instruction.context.generation, framingRevision: 1, selectionRevision: 1),
                            protagonist: selected.id, allowsReacquisition: true)
        let tracked = try engine.process(buffer([sally]), instruction: instruction, sequence: 2, observedAt: 1.2)
        #expect(tracked.candidates.contains { $0.id == selected.id && $0.continuity != .newDetection })
        let blank = try engine.process(buffer([]), instruction: instruction, sequence: 3, observedAt: 1.4)
        #expect(blank.candidates.isEmpty)
        let different = try engine.process(buffer([mae]), instruction: instruction, sequence: 4, observedAt: 1.6)
        #expect(!different.candidates.isEmpty)
        #expect(!different.candidates.contains { $0.id == selected.id })
        let returned = try engine.process(buffer([sally]), instruction: instruction, sequence: 5, observedAt: 1.8)
        #expect(returned.candidates.contains { $0.id == selected.id && $0.continuity == .reacquired })
        let nextFraming = NativeSubjectAnalysisInstruction(context: .init(generation: instruction.context.generation,
            framingRevision: 2, selectionRevision: 2), protagonist: selected.id, allowsReacquisition: true)
        let invalidated = try engine.process(buffer([sally]), instruction: nextFraming, sequence: 6, observedAt: 2)
        #expect(!invalidated.candidates.contains { $0.id == selected.id })
        engine.reset()
    }

    @Test func realVisionAmbiguousDuplicatePortraitsDoNotStealSelectedIdentity() throws {
        let engine = NativeSubjectVisionEngine(policy: policy)
        let sally = try image("sally-ride-1979")
        var instruction = instruction()
        let initial = try engine.process(buffer([sally]), instruction: instruction, sequence: 1, observedAt: 1)
        let selected = try #require(initial.candidates.first)
        instruction = .init(context: .init(generation: instruction.context.generation, framingRevision: 1, selectionRevision: 1),
                            protagonist: selected.id, allowsReacquisition: true)
        _ = try engine.process(buffer([sally]), instruction: instruction, sequence: 2, observedAt: 1.2)
        _ = try engine.process(buffer([]), instruction: instruction, sequence: 3, observedAt: 1.4)
        let duplicates = try engine.process(buffer([sally, sally]), instruction: instruction, sequence: 4, observedAt: 1.6)
        #expect(duplicates.candidates.count == 2)
        #expect(!duplicates.candidates.contains { $0.id == selected.id })
        let expired = NativeSubjectAnalysisInstruction(context: instruction.context, protagonist: selected.id, allowsReacquisition: false)
        let late = try engine.process(buffer([sally]), instruction: expired, sequence: 5, observedAt: 5)
        #expect(!late.candidates.contains { $0.id == selected.id })
        engine.reset()
    }

    @Test func realVisionBlankImageProducesConfirmedEmptyDetection() throws {
        let engine = NativeSubjectVisionEngine(policy: policy)
        let result = try engine.process(buffer([]), instruction: instruction(), sequence: 1, observedAt: 1)
        #expect(result.available)
        #expect(result.candidates.isEmpty)
    }

    @Test func temporaryPublicFixtureInferenceDiagnostics() throws {
        var features: [VNFeaturePrintObservation] = []
        for name in ["sally-ride-1979", "mae-jemison-1987"] {
            let input = try buffer([image(name)])
            CVPixelBufferLockBaseAddress(input, .readOnly)
            let data = Data(bytes: CVPixelBufferGetBaseAddress(input)!, count: CVPixelBufferGetDataSize(input))
            print("S45-DIAGNOSTIC PIXELS", name, SHA256.hash(data: data), data.count)
            let context = try #require(CGContext(data: CVPixelBufferGetBaseAddress(input), width: 512, height: 640,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(input), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            let rendered = try #require(context.makeImage())
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("s45-" + name + "-buffer.png")
            let destination = try #require(CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, rendered, nil)
            #expect(CGImageDestinationFinalize(destination))
            print("S45-DIAGNOSTIC PNG", output.path)
            CVPixelBufferUnlockBaseAddress(input, .readOnly)
            let handler = VNImageRequestHandler(cvPixelBuffer: input, orientation: .up)
            let detection = VNDetectHumanRectanglesRequest(); detection.upperBodyOnly = true
            try diagnosticCPU(detection); try handler.perform([detection])
            let observation = try #require(detection.results?.first)
            let bounds = observation.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            print("S45-DIAGNOSTIC DETECTION", name, observation.confidence, bounds)
            let feature = VNGenerateImageFeaturePrintRequest()
            feature.revision = VNGenerateImageFeaturePrintRequestRevision2
            feature.regionOfInterest = bounds; feature.imageCropAndScaleOption = .scaleFit
            try diagnosticCPU(feature); try handler.perform([feature])
            let result = try #require(feature.results?.first)
            print("S45-DIAGNOSTIC FEATURE", name, result.elementCount, SHA256.hash(data: result.data))
            features.append(result)
        }
        print("S45-DIAGNOSTIC DISTANCE", try NativeSubjectVisionEngine.distance(features[0], features[1]))
    }

    private func diagnosticCPU(_ request: VNRequest) throws {
        for (stage, devices) in try request.supportedComputeStageDevices {
            let cpu = try #require(devices.first { if case .cpu = $0 { return true }; return false })
            request.setComputeDevice(cpu, for: stage)
        }
    }

    private var policy: CaptureSubjectPolicy { .init(version: "test-only", lostGrace: 3, noPersonFocus: .tapPosition) }
    private func instruction() -> NativeSubjectAnalysisInstruction {
        .init(context: .init(generation: .init(session: .init(rawValue: "vision-fixture"), settings: 1), framingRevision: 1, selectionRevision: 0),
              protagonist: nil, allowsReacquisition: true)
    }
    private func image(_ name: String) throws -> CGImage {
        let bundle = Bundle(for: SubjectFixtureBundle.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "jpg"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    private func buffer(_ images: [CGImage]) throws -> CVPixelBuffer {
        let width = 512 * max(1, images.count), height = 640
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &result)
        #expect(status == kCVReturnSuccess)
        let buffer = try #require(result)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = try #require(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        context.setFillColor(CGColor(gray: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (index, image) in images.enumerated() {
            context.draw(image, in: CGRect(x: index * 512, y: 0, width: 512, height: 640))
        }
        return buffer
    }
}

private final class SubjectFixtureBundle: NSObject {}
