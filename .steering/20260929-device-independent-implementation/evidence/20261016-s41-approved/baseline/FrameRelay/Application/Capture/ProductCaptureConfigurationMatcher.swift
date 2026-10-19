/// A discover-time check only. Codec/manual controls still need preparation and SDK readback.
nonisolated enum ProductCaptureConfigurationMatcher {
    static func hasCurrentFormat(for configuration: CaptureConfiguration,
                                 cameras: [ExplorationCameraDescription]) -> Bool {
        guard let camera = cameras.first(where: { $0.id == configuration.camera }) else { return false }
        return camera.formats.contains { format in
            format.width == configuration.width && format.height == configuration.height
                && format.frameRateRanges.contains { $0.contains(Double(configuration.framesPerSecond)) }
                && format.logEncodings.contains(configuration.logEncoding)
                && format.stabilizationModes.contains(configuration.stabilizationMode)
        }
    }
}
