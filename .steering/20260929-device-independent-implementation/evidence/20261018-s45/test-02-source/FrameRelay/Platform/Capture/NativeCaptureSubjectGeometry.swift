import CoreGraphics

/// The data output uses pixel coordinates, while Vision and metadata use different
/// normalized spaces. Capture the SDK's full-output conversion at frame arrival.
/// This mapper applies only to the explicitly accepted unrotated, unmirrored input.
nonisolated struct NativeCaptureSubjectGeometry: Equatable, Sendable {
    let outputAreaInMetadata: CaptureSubjectRect

    static func capture(width: Int, height: Int, rotation: Double, mirrored: Bool,
                        convertPixels: (CGRect) -> CGRect) -> NativeCaptureSubjectGeometry? {
        guard width > 0, height > 0, rotation == 0, !mirrored else { return nil }
        let mapped = convertPixels(CGRect(x: 0, y: 0, width: width, height: height))
        let bounds = CaptureSubjectRect(x: mapped.minX, y: mapped.minY, width: mapped.width, height: mapped.height)
        guard bounds.isValid else { return nil }
        return .init(outputAreaInMetadata: bounds)
    }

    static func observedAt(presentationSeconds: Double, clockSeconds: Double, uptime: Double,
                           maximumAge: Double) -> Double? {
        let age = clockSeconds - presentationSeconds
        guard [presentationSeconds, clockSeconds, uptime, maximumAge].allSatisfy(\.isFinite),
              age >= 0, age <= maximumAge else { return nil }
        return uptime - age
    }

    func map(_ raw: CaptureSubjectAnalysis) -> CaptureSubjectAnalysis {
        let candidates = raw.candidates.compactMap { candidate -> CapturePersonCandidate? in
            guard let bounds = metadataBounds(fromNormalizedOutput: candidate.bounds) else { return nil }
            return .init(id: candidate.id, bounds: bounds, continuity: candidate.continuity)
        }
        // Missing geometry is uncertainty, never successful evidence of no people.
        return .init(context: raw.context, sequence: raw.sequence, observedAt: raw.observedAt,
                     candidates: candidates, available: raw.available && candidates.count == raw.candidates.count)
    }

    func metadataBounds(fromNormalizedOutput bounds: CaptureSubjectRect) -> CaptureSubjectRect? {
        guard bounds.isValid else { return nil }
        let area = outputAreaInMetadata
        let result = CaptureSubjectRect(x: area.x + bounds.x * area.width, y: area.y + bounds.y * area.height,
            width: bounds.width * area.width, height: bounds.height * area.height)
        return result.isValid ? result : nil
    }
}
