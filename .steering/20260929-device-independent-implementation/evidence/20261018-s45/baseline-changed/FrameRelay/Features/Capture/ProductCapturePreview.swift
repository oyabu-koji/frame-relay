import AVFoundation
import SwiftUI

/// Live camera surface only. Its separate preview connection does not certify the
/// recording connection's stabilization crop, even when recording stabilization is OFF.
/// No standard Rec.709 transform or S47 framing forecast is implemented here.
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
