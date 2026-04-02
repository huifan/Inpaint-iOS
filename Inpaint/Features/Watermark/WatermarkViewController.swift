//
//  WatermarkViewController.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit

class WatermarkViewController: BaseEditingViewController {

    private let processor = WatermarkProcessor()
    private var config = WatermarkConfig.defaultText()
    private var watermarkOverlay: WatermarkOverlayView!
    private var imagePicker: ImagePickerService?

    // MARK: - Init

    @MainActor override init(toolID: String) {
        super.init(toolID: toolID)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Toolbar controls

    private lazy var typeSegment: UISegmentedControl = {
        let seg = UISegmentedControl(items: [*"watermark_text", *"watermark_image"])
        seg.selectedSegmentIndex = 0
        seg.addTarget(self, action: #selector(typeChanged), for: .valueChanged)
        return seg
    }()

    private lazy var textField: UITextField = {
        let tf = UITextField()
        tf.placeholder = *"watermark_text_placeholder"
        tf.text = "Watermark"
        tf.borderStyle = .roundedRect
        tf.returnKeyType = .done
        tf.delegate = self
        tf.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        return tf
    }()

    private lazy var colorButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.layer.cornerRadius = 6
        btn.layer.borderWidth = 1
        btn.layer.borderColor = UIColor.separator.cgColor
        btn.backgroundColor = .white
        btn.addTarget(self, action: #selector(pickColor), for: .touchUpInside)
        return btn
    }()

    private lazy var opacitySlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0.1
        slider.maximumValue = 1.0
        slider.value = 0.5
        slider.addTarget(self, action: #selector(opacityChanged), for: .valueChanged)
        return slider
    }()

    private lazy var tiledSwitch: UISwitch = {
        let sw = UISwitch()
        sw.isOn = false
        sw.addTarget(self, action: #selector(tiledChanged), for: .valueChanged)
        return sw
    }()

    // Text-mode only rows
    private var textRow: UIView!
    private var colorRow: UIView!
    private weak var bottomToolbar: UIView?

    // MARK: - Setup

    override func setupToolUI() {
        if !isImageSelected {
            setupEmptyState(config: EmptyStateConfig(
                toolID: toolID,
                iconName: "signature",
                titleKey: "empty_watermark_title",
                descriptionKey: "empty_watermark_description",
                buttonTitleKey: "select_photo"
            ))
            return
        }

        setupWatermarkUI()
    }

    private func setupWatermarkUI() {
        watermarkOverlay = WatermarkOverlayView(config: config)
        watermarkOverlay.delegate = self
        watermarkOverlay.imageSize = imageView.image?.size ?? .zero
        imageView.addSubview(watermarkOverlay)
        watermarkOverlay.snp.makeConstraints { $0.edges.equalToSuperview() }

        setupBottomToolbar()
        updateColorButton()
        updateWatermark()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    // MARK: - Empty State

    override func presentImagePicker() {
        pickImageFromLibrary { [weak self] image in
            guard let self else { return }
            let scaledImage = image.scaleToLimit(size: CGSize(width: kLimitImageSize, height: kLimitImageSize))
            self.setImage(scaledImage)
        }
    }

    override func didSetImage() {
        setupWatermarkUI()
    }

    override func resetEditState() {
        super.resetEditState()
        config = WatermarkConfig.defaultText()
        watermarkOverlay?.removeFromSuperview()
        watermarkOverlay = nil
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Navigation

    override func setupNavigationItems() {
        setupUnifiedNavigationItems()

        let applyButton = UIBarButtonItem(title: *"apply", style: .done, target: self, action: #selector(onApply))
        navigationItem.rightBarButtonItems = buildRightBarButtonItems(primaryItems: [applyButton])
    }

    @objc private func onApply() {
        applyProcessing()
    }

    private func setupBottomToolbar() {
        let toolbar = UIView()
        toolbar.backgroundColor = .systemBackground
        view.addSubview(toolbar)
        bottomToolbar = toolbar

        toolbar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }

        textRow = makeRow(*"watermark_text", textField)
        colorRow = makeColorRow()

        let stack = UIStackView(arrangedSubviews: [
            makeRow(*"watermark_type", typeSegment),
            textRow!,
            colorRow!,
            makeRow(*"watermark_opacity", opacitySlider),
            makeRow(*"watermark_tiled", tiledSwitch)
        ])
        stack.axis = .vertical
        stack.spacing = 8
        toolbar.addSubview(stack)

        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(12)
        }

        scrollView.snp.remakeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(toolbar.snp.top)
        }
    }

    private func makeRow(_ label: String, _ control: UIView) -> UIView {
        let row = UIView()
        let lbl = UILabel()
        lbl.text = label
        lbl.font = .systemFont(ofSize: 14)

        row.addSubview(lbl)
        row.addSubview(control)

        row.snp.makeConstraints { make in
            make.height.equalTo(36)
        }

        lbl.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.width.equalTo(80)
        }

        control.snp.makeConstraints { make in
            make.leading.equalTo(lbl.snp.trailing).offset(8)
            make.trailing.centerY.equalToSuperview()
        }

        return row
    }

    private func makeColorRow() -> UIView {
        let row = UIView()
        let lbl = UILabel()
        lbl.text = *"watermark_color"
        lbl.font = .systemFont(ofSize: 14)

        row.addSubview(lbl)
        row.addSubview(colorButton)

        row.snp.makeConstraints { make in
            make.height.equalTo(36)
        }

        lbl.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.width.equalTo(80)
        }

        colorButton.snp.makeConstraints { make in
            make.leading.equalTo(lbl.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.width.equalTo(60)
            make.height.equalTo(28)
        }

        return row
    }

    // MARK: - Actions

    @objc private func typeChanged() {
        let isText = typeSegment.selectedSegmentIndex == 0
        textRow.isHidden = !isText
        colorRow.isHidden = !isText

        if !isText {
            let picker = ImagePickerService()
            imagePicker = picker
            picker.pickImage(from: self) { [weak self] image in
                guard let self else { return }
                guard let image = image else {
                    // User cancelled — revert to text mode
                    self.typeSegment.selectedSegmentIndex = 0
                    self.textRow.isHidden = false
                    self.colorRow.isHidden = false
                    return
                }
                self.config = WatermarkConfig(
                    type: .image(image),
                    position: self.config.position,
                    scale: 1.0,
                    rotation: self.config.rotation,
                    opacity: self.config.opacity,
                    isTiled: self.config.isTiled
                )
                self.updateWatermark()
            }
        } else {
            // Switching back to text mode
            if case .text = config.type {
                // Already text, no change needed
            } else {
                let text = textField.text?.isEmpty == false ? textField.text! : "Watermark"
                config = WatermarkConfig(
                    type: .text(text, .systemFont(ofSize: 36, weight: .bold), .white),
                    position: config.position,
                    scale: 1.0,
                    rotation: config.rotation,
                    opacity: config.opacity,
                    isTiled: config.isTiled
                )
            }
            updateColorButton()
            updateWatermark()
        }
    }

    @objc private func textChanged() {
        guard case .text(_, let font, let color) = config.type else { return }
        config = WatermarkConfig(
            type: .text(textField.text ?? "", font, color),
            position: config.position,
            scale: config.scale,
            rotation: config.rotation,
            opacity: config.opacity,
            isTiled: config.isTiled
        )
        updateWatermark()
    }

    @objc private func opacityChanged() {
        config.opacity = CGFloat(opacitySlider.value)
        updateWatermark()
    }

    @objc private func tiledChanged() {
        config.isTiled = tiledSwitch.isOn
        updateWatermark()
    }

    @objc private func pickColor() {
        let picker = UIColorPickerViewController()
        if case .text(_, _, let color) = config.type {
            picker.selectedColor = color
        }
        picker.delegate = self
        present(picker, animated: true)
    }

    private func updateTextColor(_ color: UIColor) {
        guard case .text(let text, let font, _) = config.type else { return }
        config = WatermarkConfig(
            type: .text(text, font, color),
            position: config.position,
            scale: config.scale,
            rotation: config.rotation,
            opacity: config.opacity,
            isTiled: config.isTiled
        )
        updateColorButton()
        updateWatermark()
    }

    private func updateColorButton() {
        if case .text(_, _, let color) = config.type {
            colorButton.backgroundColor = color
        }
    }

    private func updateWatermark() {
        watermarkOverlay.config = config
        watermarkOverlay.setNeedsDisplay()
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let toolbar = bottomToolbar,
              let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        let keyboardHeight = max(0, view.frame.maxY - endFrame.minY)

        toolbar.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            if keyboardHeight > 0 {
                make.bottom.equalToSuperview().offset(-keyboardHeight)
            } else {
                make.bottom.equalTo(view.safeAreaLayoutGuide)
            }
        }
        scrollView.snp.remakeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(toolbar.snp.top)
        }
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    override func currentImageForSaving(completion: @escaping (UIImage?) -> Void) {
        guard let current = imageView.image else { completion(nil); return }
        let options = ProcessingOptions(watermarkConfig: config)
        processor.process(input: ProcessingInput(image: current), options: options) { result in
            DispatchQueue.main.async { completion(result.outputImage) }
        }
    }

    func applyProcessing() {
        guard let currentImage = imageView.image else { return }
        showProcessing()
        let options = ProcessingOptions(watermarkConfig: config)
        processor.process(input: ProcessingInput(image: currentImage), options: options) { [weak self] result in
            guard let self = self else { return }
            self.hideProcessing()

            if let output = result.outputImage {
                self.pushUndo(currentImage)
                self.imageView.image = output
                self.watermarkOverlay.imageSize = output.size
            } else if let error = result.error {
                self.showError(error.localizedDescription)
            }
        }
    }
}

// MARK: - UITextFieldDelegate

extension WatermarkViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - UIColorPickerViewControllerDelegate

extension WatermarkViewController: UIColorPickerViewControllerDelegate {
    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        updateTextColor(color)
    }
}

// MARK: - WatermarkOverlayDelegate

extension WatermarkViewController: WatermarkOverlayDelegate {
    func watermarkDidUpdate(_ config: WatermarkConfig) {
        self.config = config
    }

    func watermarkSelectionDidChange(_ isSelected: Bool) {
        scrollView.isScrollEnabled = !isSelected
        scrollView.pinchGestureRecognizer?.isEnabled = !isSelected
    }
}

// MARK: - WatermarkOverlayView

class WatermarkOverlayView: UIView {
    var config: WatermarkConfig {
        didSet { updateGestureState() }
    }
    weak var delegate: WatermarkOverlayDelegate?

    /// Actual image pixel size — used to compute the content rect within the view (accounting for
    /// scaleAspectFit letterboxing). Must match the image displayed in the parent imageView.
    var imageSize: CGSize = .zero {
        didSet { setNeedsDisplay() }
    }

    /// The rect (in overlay coordinates) that the image actually occupies, excluding letterbox.
    private func imageContentRect() -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return bounds }
        let viewAspect = bounds.width / bounds.height
        let imageAspect = imageSize.width / imageSize.height
        if imageAspect > viewAspect {
            // wider image → letterbox top/bottom
            let scale = bounds.width / imageSize.width
            let h = imageSize.height * scale
            return CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
        } else {
            // taller image → letterbox left/right
            let scale = bounds.height / imageSize.height
            let w = imageSize.width * scale
            return CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
        }
    }

    private(set) var isSelected: Bool = false {
        didSet {
            updateGestureState()
            setNeedsDisplay()
            delegate?.watermarkSelectionDidChange(isSelected)
        }
    }

    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!
    private var rotateGesture: UIRotationGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    init(config: WatermarkConfig) {
        self.config = config
        super.init(frame: .zero)
        backgroundColor = .clear

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))

        panGesture.delegate = self
        pinchGesture.delegate = self
        rotateGesture.delegate = self

        addGestureRecognizer(tapGesture)
        addGestureRecognizer(panGesture)
        addGestureRecognizer(pinchGesture)
        addGestureRecognizer(rotateGesture)

        updateGestureState()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Only intercept touches on the watermark area when not selected,
    // so touches elsewhere pass through to the scroll view.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !config.isTiled else { return isSelected ? self : nil }
        if isSelected { return self }
        return isPointInWatermark(point) ? self : nil
    }

    private func updateGestureState() {
        let canMoveRotate = isSelected && !config.isTiled
        panGesture?.isEnabled = canMoveRotate
        rotateGesture?.isEnabled = canMoveRotate
        pinchGesture?.isEnabled = isSelected
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.setAlpha(config.opacity)

        if config.isTiled {
            drawTiled(in: ctx)
        } else {
            drawSingle(in: ctx)
        }

        ctx.restoreGState()

        if isSelected && !config.isTiled {
            drawSelectionIndicator()
        }
    }

    private func drawSingle(in ctx: CGContext) {
        let contentRect = imageContentRect()
        let pos = CGPoint(
            x: contentRect.origin.x + config.position.x * contentRect.width,
            y: contentRect.origin.y + config.position.y * contentRect.height
        )
        ctx.saveGState()
        ctx.translateBy(x: pos.x, y: pos.y)
        ctx.rotate(by: config.rotation)
        ctx.scaleBy(x: config.scale, y: config.scale)
        drawContent(in: ctx, referenceSize: contentRect.size)
        ctx.restoreGState()
    }

    private func drawTiled(in ctx: CGContext) {
        let spacing: CGFloat = min(bounds.width, bounds.height) * 0.35
        let angle: CGFloat = -.pi / 4
        let diagonal = sqrt(bounds.width * bounds.width + bounds.height * bounds.height)
        let count = Int(diagonal / spacing) + 2

        for i in -count...count {
            for j in -count...count {
                ctx.saveGState()
                let x = bounds.width / 2 + CGFloat(i) * spacing
                let y = bounds.height / 2 + CGFloat(j) * spacing
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: angle)
                ctx.scaleBy(x: config.scale * 0.5, y: config.scale * 0.5)
                drawContent(in: ctx, referenceSize: bounds.size)
                ctx.restoreGState()
            }
        }
    }

    private func drawContent(in ctx: CGContext, referenceSize: CGSize) {
        switch config.type {
        case .text(let text, let font, let color):
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attrs)

        case .image(let img):
            guard img.size.width > 0 else { return }
            let baseWidth = referenceSize.width * 0.3
            let aspectRatio = img.size.height / img.size.width
            let drawSize = CGSize(width: baseWidth, height: baseWidth * aspectRatio)
            img.draw(in: CGRect(x: -drawSize.width / 2, y: -drawSize.height / 2,
                                width: drawSize.width, height: drawSize.height))
        }
    }

    private func drawSelectionIndicator() {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let contentRect = imageContentRect()
        let pos = CGPoint(
            x: contentRect.origin.x + config.position.x * contentRect.width,
            y: contentRect.origin.y + config.position.y * contentRect.height
        )
        let size = watermarkContentSize()
        let w = size.width * config.scale + 16
        let h = size.height * config.scale + 16

        ctx.saveGState()
        // Apply same transform as the watermark so the box rotates with it
        ctx.translateBy(x: pos.x, y: pos.y)
        ctx.rotate(by: config.rotation)

        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 3])
        ctx.stroke(rect)

        let handleSize: CGFloat = 9
        let corners: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setFillColor(UIColor.white.cgColor)
        for corner in corners {
            let hr = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2,
                            width: handleSize, height: handleSize)
            ctx.fillEllipse(in: hr)
            ctx.strokeEllipse(in: hr)
        }
        ctx.restoreGState()
    }

    private func watermarkContentSize() -> CGSize {
        let contentRect = imageContentRect()
        switch config.type {
        case .text(let text, let font, _):
            return text.size(withAttributes: [.font: font])
        case .image(let img):
            let baseWidth = contentRect.width * 0.3
            return CGSize(width: baseWidth,
                          height: baseWidth * img.size.height / max(img.size.width, 1))
        }
    }

    // Checks if point is inside the rotated watermark bounds.
    private func isPointInWatermark(_ point: CGPoint) -> Bool {
        let contentRect = imageContentRect()
        let pos = CGPoint(
            x: contentRect.origin.x + config.position.x * contentRect.width,
            y: contentRect.origin.y + config.position.y * contentRect.height
        )
        let size = watermarkContentSize()
        let hw = size.width * config.scale / 2 + 20
        let hh = size.height * config.scale / 2 + 20
        // Rotate the point into the watermark's local coordinate space
        let dx = point.x - pos.x
        let dy = point.y - pos.y
        let localX = dx * cos(-config.rotation) - dy * sin(-config.rotation)
        let localY = dx * sin(-config.rotation) + dy * cos(-config.rotation)
        return abs(localX) <= hw && abs(localY) <= hh
    }

    // MARK: - Gestures

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if isSelected {
            if !isPointInWatermark(point) {
                isSelected = false
            }
        } else {
            isSelected = true
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !config.isTiled else { return }
        let contentRect = imageContentRect()
        let translation = gesture.translation(in: self)
        config.position.x = max(0, min(1, config.position.x + translation.x / contentRect.width))
        config.position.y = max(0, min(1, config.position.y + translation.y / contentRect.height))
        gesture.setTranslation(.zero, in: self)
        delegate?.watermarkDidUpdate(config)
        setNeedsDisplay()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        config.scale = max(0.1, min(5.0, config.scale * gesture.scale))
        gesture.scale = 1.0
        delegate?.watermarkDidUpdate(config)
        setNeedsDisplay()
    }

    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        guard !config.isTiled else { return }
        config.rotation += gesture.rotation
        gesture.rotation = 0
        delegate?.watermarkDidUpdate(config)
        setNeedsDisplay()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension WatermarkOverlayView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Allow pinch + rotate to work together on the watermark
        return true
    }
}

protocol WatermarkOverlayDelegate: AnyObject {
    func watermarkDidUpdate(_ config: WatermarkConfig)
    func watermarkSelectionDidChange(_ isSelected: Bool)
}
