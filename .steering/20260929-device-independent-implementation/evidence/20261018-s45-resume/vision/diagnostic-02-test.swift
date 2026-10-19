import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import Testing
import Vision
import CoreML
import CoreImage
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

    @Test func temporaryFeatureTransportDiagnostics() throws {
        var features: [String: [VNFeaturePrintObservation]] = [:]
        for name in ["sally-ride-1979", "mae-jemison-1987"] {
            let source = try image(name)
            let input = try buffer([source])
            let detection = VNDetectHumanRectanglesRequest(); detection.upperBodyOnly = true
            try diagnosticCPU(detection)
            let original = VNImageRequestHandler(cvPixelBuffer: input, orientation: .up)
            try original.perform([detection])
            let bounds = try #require(detection.results?.first?.boundingBox).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            CVPixelBufferLockBaseAddress(input, .readOnly)
            let bitmap = try #require(CGContext(data: CVPixelBufferGetBaseAddress(input), width: 512, height: 640,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(input), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            let rendered = try #require(bitmap.makeImage())
            CVPixelBufferUnlockBaseAddress(input, .readOnly)
            let cropBounds = CGRect(x: bounds.minX * 512, y: (1 - bounds.maxY) * 640,
                                    width: bounds.width * 512, height: bounds.height * 640).integral
            let crop = try #require(rendered.cropping(to: cropBounds))
            print("S45-TRANSPORT DETECTION", name, bounds, "crop", crop.width, crop.height)
            for compute in ["stage", "legacy", "automatic"] {
                let revision = VNGenerateImageFeaturePrintRequestRevision2
                for software in [false, true] {
                    let scale = VNImageCropAndScaleOption.scaleFit
                    let options: [VNImageOption: Any] = [.ciContext: CIContext(options: [.useSoftwareRenderer: software])]
                    for mode in ["pixel-roi", "cg-crop", "jpeg-original"] {
                        let key = "\(compute)-software\(software)-\(mode)"
                        do {
                            let feature = VNGenerateImageFeaturePrintRequest()
                            feature.revision = revision; feature.imageCropAndScaleOption = scale
                            if mode.hasSuffix("roi") { feature.regionOfInterest = bounds }
                            if compute == "stage" { try diagnosticCPU(feature) }
                            if compute == "legacy" { feature.usesCPUOnly = true }
                            let handler: VNImageRequestHandler
                            switch mode {
                            case "pixel-roi", "pixel-full": handler = VNImageRequestHandler(cvPixelBuffer: input, orientation: .up, options: options)
                            case "cg-crop": handler = VNImageRequestHandler(cgImage: crop, orientation: .up, options: options)
                            case "jpeg-original": handler = VNImageRequestHandler(cgImage: source, orientation: .up, options: options)
                            default: handler = VNImageRequestHandler(cgImage: rendered, orientation: .up, options: options)
                            }
                            try handler.perform([feature])
                            let value = try #require(feature.results?.first)
                            features[key, default: []].append(value)
                            print("S45-TRANSPORT FEATURE", name, key, value.elementCount, SHA256.hash(data: value.data))
                        } catch { print("S45-TRANSPORT ERROR", name, key, error) }
                    }
                }
            }
        }
        for key in features.keys.sorted() {
            if let pair = features[key], pair.count == 2 {
                print("S45-TRANSPORT DISTANCE", key, try NativeSubjectVisionEngine.distance(pair[0], pair[1]))
            }
        }
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
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        context.setAlpha(1)
        context.setFillColor(CGColor(gray: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (index, image) in images.enumerated() {
            context.draw(image, in: CGRect(x: index * 512, y: 0, width: 512, height: 640))
        }
        let bytes = UnsafeRawBufferPointer(start: CVPixelBufferGetBaseAddress(buffer), count: CVPixelBufferGetDataSize(buffer))
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let opaque = (0..<height).allSatisfy { row in
            (0..<width).allSatisfy { column in bytes[row * rowBytes + column * 4 + 3] == 255 }
        }
        #expect(opaque, "Public fixture BGRA pixels must have explicit opaque alpha before real Vision inference")
        return buffer
    }
}

private final class SubjectFixtureBundle: NSObject {}
