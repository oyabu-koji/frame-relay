import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

nonisolated struct CaptureDisplayContext: Equatable, Sendable {
    let generation: CaptureGeneration
    let displayRevision: UInt64
}

/// A display-only immutable image. There is no output CVPixelBuffer, sample buffer,
/// or writer handle. No product camera, preview, or factory consumes this yet.
nonisolated struct CaptureDisplayFrame: Sendable {
    enum Use: Equatable, Sendable { case technicalFixture }
    let image: CGImage
    let context: CaptureDisplayContext
    let sequence: UInt64
    let transformID: String
    let transformVersion: String
    let transformSHA256: String
    let use = Use.technicalFixture
}

nonisolated final class CaptureDisplayRenderer: Sendable {
    enum InputOrigin: Equatable, Sendable { case captureOriginal, displayConverted }
    // CIContext is reusable across threads; all per-draw images/filters are local.
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])

    /// The producer must keep the capture buffer immutable while this synchronous
    /// read runs (and, for the pipeline, until its retained input is released).
    /// Encoded fixture drawing disables implicit color management; it is not a
    /// standard color-space conversion, even when the input is tagged Rec.709.
    func render(_ buffer: CVPixelBuffer, origin: InputOrigin, context displayContext: CaptureDisplayContext,
                sequence: UInt64, transform: CaptureDisplayTransform) throws -> CaptureDisplayFrame {
        guard origin == .captureOriginal else { throw CaptureDisplayError.alreadyConverted }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
            throw CaptureDisplayError.unsupportedPixelFormat
        }
        func tag(_ key: CFString) -> String? { CVBufferCopyAttachment(buffer, key, nil) as? String }
        let transfer = tag(kCVImageBufferTransferFunctionKey)
        let expected = transform.inputSignal == .sRGB ? kCVImageBufferTransferFunction_sRGB : kCVImageBufferTransferFunction_ITU_R_709_2
        guard tag(kCVImageBufferLogTransferFunctionKey) == nil,
              tag(kCVImageBufferColorPrimariesKey) == kCVImageBufferColorPrimaries_ITU_R_709_2 as String,
              transfer == expected as String,
              tag(kCVImageBufferYCbCrMatrixKey) == nil || tag(kCVImageBufferYCbCrMatrixKey) == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String else {
            throw CaptureDisplayError.signalMismatch
        }
        let input = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        guard let cube = CIFilter(name: "CIColorCube") else { throw CaptureDisplayError.renderFailed }
        cube.setValue(input, forKey: kCIInputImageKey)
        cube.setValue(transform.dimension, forKey: "inputCubeDimension")
        cube.setValue(transform.rgbaCube, forKey: "inputCubeData")
        guard let filtered = cube.outputImage,
              let image = context.createCGImage(filtered, from: input.extent, format: .RGBA8, colorSpace: nil, deferred: false) else {
            throw CaptureDisplayError.renderFailed
        }
        return .init(image: image, context: displayContext, sequence: sequence, transformID: transform.identifier,
                     transformVersion: transform.version, transformSHA256: transform.sha256)
    }
}
