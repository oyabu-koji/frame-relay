import CoreVideo
import Foundation

nonisolated struct NativeCaptureNDTarget: Equatable, Sendable {
    let person: CapturePersonID
    let bounds: CaptureSubjectRect // normalized input-buffer coordinates, top left
}
nonisolated struct NativeCaptureNDInstruction: Equatable, Sendable {
    let context: CaptureNDContext
    let targets: [NativeCaptureNDTarget]
    let targetsAvailable: Bool
}

/// Reads the immutable analysis branch only. No rendering, camera command or writer access.
nonisolated enum NativeCaptureNDPixels {
    static func signal(_ buffer: CVPixelBuffer) -> CaptureNDSignal? {
        func tag(_ key: CFString) -> String? { CVBufferCopyAttachment(buffer, key, nil) as? String }
        let primaries = tag(kCVImageBufferColorPrimariesKey)
        let transfer = tag(kCVImageBufferTransferFunctionKey)
        let matrix = tag(kCVImageBufferYCbCrMatrixKey)
        let log = tag(kCVImageBufferLogTransferFunctionKey)
        let bgra = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA
        if let log {
            guard !bgra, matrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 as String else { return nil }
            if log == kCVImageBufferLogTransferFunction_AppleLog as String,
               primaries == kCVImageBufferColorPrimaries_ITU_R_2020 as String,
               transfer == nil || transfer == kCVImageBufferTransferFunction_Linear as String {
                return .appleLog
            }
            // CVImageBuffer.h explicitly defines Log2 as a whole color space, with
            // absent/undefined primaries and transfer and a 2020 YCbCr matrix.
            if log == kCVImageBufferLogTransferFunction_AppleLog2 as String,
               primaries == nil, transfer == nil { return .appleLog2 }
            return nil
        }
        guard primaries == kCVImageBufferColorPrimaries_ITU_R_709_2 as String,
              bgra || matrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String else { return nil }
        if transfer == kCVImageBufferTransferFunction_ITU_R_709_2 as String { return .rec709 }
        if transfer == kCVImageBufferTransferFunction_sRGB as String { return .sRGB }
        return nil
    }

    static func evaluate(_ buffer: CVPixelBuffer, instruction: NativeCaptureNDInstruction,
                         policy: CaptureNDPolicy, sequence: UInt64, observedAt: TimeInterval) -> CaptureNDResult {
        func result(_ advice: CaptureNDAdvice, _ evidence: CaptureNDEvidence? = nil) -> CaptureNDResult {
            .init(context: instruction.context, sequence: sequence, observedAt: observedAt, advice: advice, evidence: evidence)
        }
        guard policy.isValid else { return result(.pending(.policyUnavailable)) }
        guard let intent = instruction.context.intent else { return result(.pending(.selectIntent)) }
        guard let signal = signal(buffer), let band = policy.bands[signal] else { return result(.pending(.unknownSignal)) }
        if intent != .scenery {
            guard !instruction.targets.isEmpty else { return result(.pending(.selectPeople)) }
            guard instruction.targetsAvailable else { return result(.pending(.missingPeople)) }
        }
        guard let samples = read(buffer), !samples.isEmpty else { return result(.pending(.insufficientSignal)) }
        let scene = statistics(samples.map(\.value), person: nil, band: band)
        var people: [CaptureNDRegionEvidence] = []
        for target in instruction.targets {
            guard target.bounds.isValid else { return result(.pending(.missingPeople)) }
            people.append(statistics(samples.filter { contains(target.bounds, $0) }.map(\.value), person: target.person, band: band))
        }
        let background = instruction.targets.isEmpty ? nil : statistics(samples.filter { sample in
            !instruction.targets.contains { contains($0.bounds, sample) }
        }.map(\.value), person: nil, band: band)
        let evidence = CaptureNDEvidence(signal: signal, policyVersion: policy.version,
            scene: scene, people: people, background: background)
        let relevant = intent == .scenery ? [scene] : people
        // A selected but undersampled, flat, clipped or black region cannot silently
        // disappear from a multiple-person decision. Extreme values provide no headroom.
        if relevant.contains(where: { $0.clippedFraction > 0.95 }) { return result(.pending(.saturated), evidence) }
        guard relevant.allSatisfy({ usable($0, band: band) }) else { return result(.pending(.insufficientSignal), evidence) }
        let directions = relevant.map { direction($0, band: band) }
        if directions.contains(.darker) && directions.contains(.lighter) {
            return result(.init(direction: .difficult, reasons: [.conflictingPeople]), evidence)
        }
        let primary: CaptureNDDirection = directions.contains(.darker) ? .darker : directions.contains(.lighter) ? .lighter : .acceptable
        if intent != .scenery, let background, usable(background, band: band) {
            let other = direction(background, band: band)
            if (primary == .lighter && other == .darker) || (primary == .darker && other == .lighter) {
                return result(.init(direction: .difficult, reasons: [.peopleAndBackgroundConflict]), evidence)
            }
            if intent == .peopleAndBackground, primary == .acceptable, other != .acceptable {
                return result(.init(direction: .difficult, reasons: [.peopleAndBackgroundConflict]), evidence)
            }
        } else if intent == .peopleAndBackground {
            return result(.pending(.insufficientSignal), evidence)
        }
        let reason: CaptureNDReason = primary == .acceptable ? .withinReference : primary == .darker
            ? (intent == .scenery ? .broadHighlights : .selectedPeopleBright)
            : (intent == .scenery ? .broadShadows : .selectedPeopleDark)
        return result(.init(direction: primary, reasons: [reason]), evidence)
    }

    private static func usable(_ value: CaptureNDRegionEvidence, band: CaptureNDBand) -> Bool {
        value.sampleCount >= 16 && value.upper - value.lower >= band.minimumSpread
            && value.median > 0.02 && value.clippedFraction <= 0.95
    }
    private static func direction(_ value: CaptureNDRegionEvidence, band: CaptureNDBand) -> CaptureNDDirection {
        if value.median > band.high && value.brightFraction >= band.broadFraction { return .darker }
        if value.median < band.low && value.darkFraction >= band.broadFraction { return .lighter }
        return .acceptable
    }
    private static func statistics(_ values: [Double], person: CapturePersonID?, band: CaptureNDBand) -> CaptureNDRegionEvidence {
        let ordered = values.sorted()
        func quantile(_ fraction: Double) -> Double { ordered.isEmpty ? 0 : ordered[Int(Double(ordered.count - 1) * fraction)] }
        let count = Double(max(1, values.count))
        return .init(person: person, sampleCount: values.count, lower: quantile(0.2), median: quantile(0.5), upper: quantile(0.8),
            darkFraction: Double(values.filter { $0 < band.low }.count) / count,
            brightFraction: Double(values.filter { $0 > band.high }.count) / count,
            clippedFraction: Double(values.filter { $0 >= 1 }.count) / count)
    }
    private struct Sample { let x: Double; let y: Double; let value: Double }
    private static func contains(_ rect: CaptureSubjectRect, _ sample: Sample) -> Bool {
        sample.x >= rect.x && sample.x < rect.x + rect.width && sample.y >= rect.y && sample.y < rect.y + rect.height
    }
    private static func read(_ buffer: CVPixelBuffer) -> [Sample]? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let bytes: Int, black: Double, white: Double, bgra: Bool
        switch format {
        case kCVPixelFormatType_32BGRA: bytes = 4; black = 0; white = 255; bgra = true
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: bytes = 1; black = 16; white = 235; bgra = false
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: bytes = 1; black = 0; white = 255; bgra = false
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: bytes = 2; black = 64; white = 940; bgra = false
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: bytes = 2; black = 0; white = 1023; bgra = false
        default: return nil
        }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard bgra ? !CVPixelBufferIsPlanar(buffer) : CVPixelBufferGetPlaneCount(buffer) == 2 else { return nil }
        let width = bgra ? CVPixelBufferGetWidth(buffer) : CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = bgra ? CVPixelBufferGetHeight(buffer) : CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = bgra ? CVPixelBufferGetBytesPerRow(buffer) : CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pointer = bgra ? CVPixelBufferGetBaseAddress(buffer) : CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        guard let pointer, width > 0, height > 0, rowBytes >= width * bytes else { return nil }
        // At most 96 × 96 pixels; no retained full-frame copy, histogram or image in UI.
        let columns = min(width, 96), rows = min(height, 96)
        var values: [Sample] = []; values.reserveCapacity(columns * rows)
        for row in 0..<rows {
            let y = min(height - 1, Int((Double(row) + 0.5) * Double(height) / Double(rows)))
            for column in 0..<columns {
                let x = min(width - 1, Int((Double(column) + 0.5) * Double(width) / Double(columns)))
                let pixel = pointer.advanced(by: y * rowBytes + x * bytes)
                let code: Double
                if bgra {
                    let b = Double(pixel.load(fromByteOffset: 0, as: UInt8.self))
                    let g = Double(pixel.load(fromByteOffset: 1, as: UInt8.self))
                    let r = Double(pixel.load(fromByteOffset: 2, as: UInt8.self))
                    code = 0.2126 * r + 0.7152 * g + 0.0722 * b
                } else if bytes == 2 { code = Double(pixel.load(as: UInt16.self) >> 6) }
                else { code = Double(pixel.load(as: UInt8.self)) }
                values.append(.init(x: (Double(x) + 0.5) / Double(width), y: (Double(y) + 0.5) / Double(height),
                    value: (code - black) / (white - black)))
            }
        }
        return values
    }
}
