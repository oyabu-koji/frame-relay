import Foundation
import ImageIO
import Vision
let base = URL(fileURLWithPath: "/private/tmp/fr-s45-20261018-ow_sx8bp/fixtures")
var prints: [VNFeaturePrintObservation] = []
for name in ["sally-ride-1979", "mae-jemison-1987"] {
    let url = base.appendingPathComponent(name + ".jpg")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("fixture decode") }
    let request = VNDetectHumanRectanglesRequest()
    request.upperBodyOnly = true
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    let observations = request.results ?? []
    print(name, "humanCount", observations.count, "confidence", observations.map(\.confidence))
    let feature = VNGenerateImageFeaturePrintRequest()
    feature.revision = VNGenerateImageFeaturePrintRequestRevision2
    if let observation = observations.max(by: { $0.confidence < $1.confidence }) { feature.regionOfInterest = observation.boundingBox }
    try handler.perform([feature])
    if let value = feature.results?.first { prints.append(value) }
}
if prints.count == 2 {
    var same: Float = 0
    var different: Float = 0
    try prints[0].computeDistance(&same, to: prints[0])
    try prints[0].computeDistance(&different, to: prints[1])
    print("featurePrintRevision2 same", same, "different", different)
}
