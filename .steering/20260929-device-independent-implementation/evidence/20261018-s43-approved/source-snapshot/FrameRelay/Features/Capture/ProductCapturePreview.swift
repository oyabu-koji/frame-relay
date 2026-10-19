import AVFoundation
import SwiftUI

/// Camera framing only. This layer does not claim a standard Rec.709 transform.
struct ProductCapturePreview: UIViewRepresentable {
    let source: NativeCapturePreviewSource

    func makeUIView(context: Context) -> ProductCapturePreviewSurface {
        let view = ProductCapturePreviewSurface()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = source.session
        return view
    }

    func updateUIView(_ view: ProductCapturePreviewSurface, context: Context) {
        if view.previewLayer.session !== source.session { view.previewLayer.session = source.session }
    }

    static func dismantleUIView(_ view: ProductCapturePreviewSurface, coordinator: ()) {
        view.previewLayer.session = nil
    }
}

final class ProductCapturePreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
