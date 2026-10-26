import AVFoundation
import SwiftUI

/// Live camera surface only. SDK coordinate conversion handles orientation, mirroring
/// and aspect-fit letterboxing; corrected recording/preview FOV still needs DV-04/06.
/// The ratio guide belongs only to this preview layer, never a recording output.
struct ProductCapturePreview: UIViewRepresentable {
    let source: NativeCapturePreviewSource
    var subjects: CaptureSubjectSnapshot? = nil
    var allowsSceneTap = false
    var zoomForecast: CaptureZoomForecast? = nil
    var onCommand: (CaptureSubjectCommand) -> Void = { _ in }

    func makeUIView(context: Context) -> ProductCapturePreviewSurface {
        let view = ProductCapturePreviewSurface()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = source.session
        view.onCommand = onCommand
        return view
    }

    func updateUIView(_ view: ProductCapturePreviewSurface, context: Context) {
        if view.previewLayer.session !== source.session { view.previewLayer.session = source.session }
        view.subjects = subjects
        view.allowsSceneTap = allowsSceneTap
        view.zoomForecast = zoomForecast
        view.onCommand = onCommand
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: ProductCapturePreviewSurface, coordinator: ()) {
        view.subjects = nil
        view.zoomForecast = nil
        view.onCommand = { _ in }
        view.previewLayer.session = nil
    }
}

final class ProductCapturePreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var subjects: CaptureSubjectSnapshot?
    var allowsSceneTap = false
    var zoomForecast: CaptureZoomForecast?
    var onCommand: (CaptureSubjectCommand) -> Void = { _ in }
    private var boxes: [CAShapeLayer] = []
    private var labels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        boxes.forEach { $0.removeFromSuperlayer() }; boxes = []
        labels.forEach { $0.removeFromSuperview() }; labels = []
        if let forecast = zoomForecast, !forecast.isWider {
            let visible = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            let guide = forecast.guide
            let rect = CGRect(x: visible.minX + visible.width * guide.x, y: visible.minY + visible.height * guide.y,
                              width: visible.width * guide.width, height: visible.height * guide.height)
            let box = CAShapeLayer()
            box.path = UIBezierPath(rect: rect).cgPath
            box.fillColor = UIColor.clear.cgColor; box.strokeColor = UIColor.systemCyan.cgColor
            box.lineWidth = 2; box.lineDashPattern = [8, 4]
            layer.addSublayer(box); boxes.append(box)
        }
        for (index, person) in (subjects?.candidates ?? []).enumerated() {
            let rect = converted(person.bounds)
            let box = CAShapeLayer()
            box.path = UIBezierPath(rect: rect).cgPath
            box.fillColor = UIColor.clear.cgColor
            let selected = subjects?.protagonist == person.id
            box.strokeColor = (selected ? UIColor.systemYellow : UIColor.white).cgColor
            box.lineWidth = selected ? 3 : 1.5
            if subjects?.exposureTargets.contains(person.id) == true { box.lineDashPattern = [6, 3] }
            layer.addSublayer(box); boxes.append(box)
            let label = UILabel()
            label.text = "\(index + 1)" + (selected ? " 主役" : "")
            label.font = .preferredFont(forTextStyle: .caption1)
            label.textColor = selected ? .systemYellow : .white
            label.backgroundColor = .black.withAlphaComponent(0.7)
            label.sizeToFit()
            label.frame.origin = CGPoint(x: rect.minX, y: max(0, rect.minY))
            label.isAccessibilityElement = false // The equivalent SwiftUI buttons expose the actions.
            addSubview(label); labels.append(label)
        }
    }

    private func converted(_ bounds: CaptureSubjectRect) -> CGRect {
        previewLayer.layerRectConverted(fromMetadataOutputRect:
            CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height))
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        if let person = subjects?.candidates.filter({ converted($0.bounds).contains(location) })
            .min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
            onCommand(.selectProtagonist(person.id))
        } else if allowsSceneTap, subjects?.candidates.isEmpty == true {
            let visible = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            guard visible.contains(location) else { return }
            let point = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
            let normalized = CaptureSubjectPoint(x: point.x, y: point.y)
            if normalized.isValid { onCommand(.scenePoint(normalized)) }
        }
    }
}
