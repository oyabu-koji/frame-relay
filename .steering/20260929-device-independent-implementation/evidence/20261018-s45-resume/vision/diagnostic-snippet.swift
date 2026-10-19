    @Test func temporaryFeatureTransportDiagnostics() throws {
        var features: [String: [VNFeaturePrintObservation]] = [:]
        for name in ["sally-ride-1979", "mae-jemison-1987"] {
            let source = try image(name)
            let input = try buffer([source])
            let detection = VNDetectHumanRectanglesRequest(); detection.upperBodyOnly = true
            try diagnosticCPU(detection)
            let original = VNImageRequestHandler(cvPixelBuffer: input, orientation: .up)
            try original.perform([detection])
            let bounds = try #require(detection.results?.first?.boundingBox)
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
            for revision in [VNGenerateImageFeaturePrintRequestRevision1, VNGenerateImageFeaturePrintRequestRevision2] {
                for scale in [VNImageCropAndScaleOption.scaleFit, .scaleFill, .centerCrop] {
                    for mode in ["pixel-roi", "pixel-full", "cg-roi", "cg-full", "cg-crop", "jpeg-original"] {
                        let key = "r\(revision)-s\(scale.rawValue)-\(mode)"
                        do {
                            let feature = VNGenerateImageFeaturePrintRequest()
                            feature.revision = revision; feature.imageCropAndScaleOption = scale
                            if mode.hasSuffix("roi") { feature.regionOfInterest = bounds }
                            try diagnosticCPU(feature)
                            let handler: VNImageRequestHandler
                            switch mode {
                            case "pixel-roi", "pixel-full": handler = VNImageRequestHandler(cvPixelBuffer: input, orientation: .up)
                            case "cg-crop": handler = VNImageRequestHandler(cgImage: crop, orientation: .up)
                            case "jpeg-original": handler = VNImageRequestHandler(cgImage: source, orientation: .up)
                            default: handler = VNImageRequestHandler(cgImage: rendered, orientation: .up)
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

