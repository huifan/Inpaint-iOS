//
//  InpaintViewController.swift
//  Inpaint
//
//  Refactored on 2026/03/30.
//  Updated on 2026/03/31 with SAM tap-to-select and model switching.
//

import UIKit
import SnapKit
import Toast_Swift

class InpaintViewController: BaseEditingViewController {

    override var toolID: String { "inpainting" }

    private let processor = InpaintProcessor()
    private let samHelper = SAMSegmentHelper.shared

    private lazy var drawView: SmudgeDrawingView = {
        let view = SmudgeDrawingView()
        return view
    }()

    private lazy var selectionOverlay: SelectionOverlayView = {
        let view = SelectionOverlayView()
        return view
    }()

    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        return gesture
    }()

    private var hasWarned = false

    // Progress simulation
    private var progressTimer: Timer?

    // MARK: - Setup

    private var isDrawMode = true {
        didSet { applyInteractionMode() }
    }

    private lazy var modeToggleButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "pencil.tip"), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = .systemBlue
        btn.layer.cornerRadius = 20
        btn.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
        return btn
    }()

    private lazy var brushPreview: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 0.5)
        v.layer.cornerRadius = 10
        v.isUserInteractionEnabled = false
        return v
    }()

    private lazy var brushSizeLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    override func setupToolUI() {
        // Preload model synchronously on first setup
        processor.preload()

        imageView.addSubview(drawView)
        drawView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 涂抹完成后启用撤销按钮
        drawView.onStrokeCompleted = { [weak self] in
            self?.updateUndoButtonState()
        }

        imageView.addSubview(selectionOverlay)
        selectionOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // Add tap gesture for SAM-based selection
        imageView.addGestureRecognizer(tapGesture)

        // Brush size toolbar at bottom
        let lastValue = UserDefaults.standard.object(forKey: "lastSliderValue") as? Float ?? 15
        drawView.brushSize = CGFloat(lastValue)

        let toolbar = UIView()
        toolbar.backgroundColor = .systemBackground
        view.addSubview(toolbar)

        // 模式切换按钮
        toolbar.addSubview(modeToggleButton)
        modeToggleButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(40)
        }

        let brushLabel = UILabel()
        brushLabel.text = *"brush_size"
        brushLabel.font = .systemFont(ofSize: 13)
        brushLabel.textColor = .secondaryLabel

        let slider = UISlider()
        slider.minimumValue = 5
        slider.maximumValue = 80
        slider.value = lastValue
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)

        toolbar.addSubview(brushPreview)
        toolbar.addSubview(brushLabel)
        toolbar.addSubview(slider)
        toolbar.addSubview(brushSizeLabel)

        toolbar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(56)
        }

        brushPreview.snp.makeConstraints { make in
            make.leading.equalTo(modeToggleButton.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(min(max(CGFloat(lastValue), 10), 40))
        }

        brushLabel.snp.makeConstraints { make in
            make.leading.equalTo(brushPreview.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
        }

        brushSizeLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(30)
        }

        slider.snp.makeConstraints { make in
            make.leading.equalTo(brushLabel.snp.trailing).offset(8)
            make.trailing.equalTo(brushSizeLabel.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }

        updateBrushPreview(size: CGFloat(lastValue))

        scrollView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(toolbar.snp.top)
        }

        // 默认涂抹模式
        applyInteractionMode()
    }

    // MARK: - Undo (涂抹笔画 + 消除操作)

    override func onUndo() {
        // 优先撤销涂抹笔画
        if drawView.hasStrokes {
            drawView.undoLastStroke()
            updateUndoButtonState()
            return
        }
        // 没有笔画了，撤销消除操作
        super.onUndo()
        updateUndoButtonState()
    }

    private func updateUndoButtonState() {
        undoButton.isEnabled = drawView.hasStrokes || canUndo
    }

    override func setupNavigationItems() {
        undoButton.isEnabled = false

        // Back button
        let backButton = UIBarButtonItem(title: *"back", style: .plain, target: self, action: #selector(onBack))

        let inpaintButton = UIBarButtonItem(title: *"inpaint", style: .plain, target: self, action: #selector(onInpaint))
        let saveButton = UIBarButtonItem(title: *"save_to_photo_lib", style: .plain, target: self, action: #selector(onSave))
        compareButton = makeCompareButton()

        // Left side: back
        navigationItem.leftBarButtonItems = [backButton]

        // Right side: compare, save, inpaint, undo
        navigationItem.rightBarButtonItems = [compareButton!, saveButton, inpaintButton, undoButton]
    }

    // MARK: - Actions

    @objc private func onBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func toggleMode() {
        isDrawMode.toggle()
    }

    private func applyInteractionMode() {
        if isDrawMode {
            // 涂抹模式：单指涂抹，禁止滚动/缩放
            drawView.isUserInteractionEnabled = true
            scrollView.isScrollEnabled = false
            scrollView.pinchGestureRecognizer?.isEnabled = false
            modeToggleButton.setImage(UIImage(systemName: "pencil.tip"), for: .normal)
            modeToggleButton.backgroundColor = .systemBlue
        } else {
            // 移动模式：单指平移，双指缩放，禁止涂抹
            drawView.isUserInteractionEnabled = false
            scrollView.isScrollEnabled = true
            scrollView.pinchGestureRecognizer?.isEnabled = true
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
            modeToggleButton.setImage(UIImage(systemName: "hand.draw"), for: .normal)
            modeToggleButton.backgroundColor = .systemGray
        }
    }

    @objc private func sliderValueChanged(_ sender: UISlider) {
        let roundedValue = round(sender.value)
        UserDefaults.standard.set(roundedValue, forKey: "lastSliderValue")
        drawView.brushSize = CGFloat(roundedValue)
        updateBrushPreview(size: CGFloat(roundedValue))
    }

    private func updateBrushPreview(size: CGFloat) {
        let displaySize = min(max(size, 10), 40)
        brushPreview.snp.updateConstraints { make in
            make.width.height.equalTo(displaySize)
        }
        brushPreview.layer.cornerRadius = displaySize / 2.0
        brushSizeLabel.text = "\(Int(size))"
    }

    // MARK: - Tap to Select (SAM)

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let tapPoint = gesture.location(in: imageView)

        // Check if SAM is available
        if samHelper.isAvailable {
            performSAMSelection(at: tapPoint)
        } else {
            // Show hint about drawing to select
            view.makeToast(*"inpaint_tap_select", duration: 2.0, position: .bottom)
        }
    }

    private func performSAMSelection(at point: CGPoint) {
        guard let image = imageView.image else { return }

        showProcessing(message: *"processing")

        Task {
            do {
                // Generate mask using SAM
                let mask = try await samHelper.segment(
                    at: .foreground(at: point),
                    imageSize: image.size
                )

                await MainActor.run {
                    self.hideProcessing()

                    // Add to selection overlay
                    self.selectionOverlay.addSelection(from: mask)

                    // Also draw on SmudgeDrawingView for refinement
                    self.addMaskToDrawView(mask)

                    self.view.makeToast(*"inpaint_object_selected", duration: 1.5, position: .bottom)
                }
            } catch {
                await MainActor.run {
                    self.hideProcessing()
                    // Fallback to saliency if SAM fails
                    self.performSaliencySelection(at: point)
                }
            }
        }
    }

    private func performSaliencySelection(at point: CGPoint) {
        guard let image = imageView.image else { return }

        Task {
            do {
                if let mask = try await samHelper.generateSaliencyMask(for: image, near: point) {
                    await MainActor.run {
                        self.hideProcessing()
                        self.selectionOverlay.addSelection(from: mask)
                        self.addMaskToDrawView(mask)
                        self.view.makeToast(*"inpaint_object_selected", duration: 1.5, position: .bottom)
                    }
                } else {
                    await MainActor.run {
                        self.hideProcessing()
                        self.view.makeToast(*"inpaint_no_object_found", duration: 2.0, position: .bottom)
                    }
                }
            } catch {
                await MainActor.run {
                    self.hideProcessing()
                    self.view.makeToast(error.localizedDescription, duration: 2.0, position: .bottom)
                }
            }
        }
    }

    private func addMaskToDrawView(_ mask: UIImage) {
        // Convert mask to drawing-compatible format
        // This adds the detected region to the smudge drawing for refinement
        guard let cgImage = mask.cgImage else { return }

        let width = cgImage.width
        let height = cgImage.height
        let scale = UIScreen.main.scale

        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let stride = cgImage.bytesPerRow

        var rects: [CGRect] = []

        // Find connected white regions
        for y in stride..<(height - stride) {
            for x in 1..<(width - 1) {
                let idx = y * stride + x * bytesPerPixel
                let alpha = bytesPerPixel >= 4 ? bytes[idx + 3] : bytes[idx]

                if alpha > 128 {
                    // Found a white pixel - add surrounding region
                    let expand: CGFloat = 10
                    let rect = CGRect(
                        x: CGFloat(x) / scale - expand,
                        y: CGFloat(y) / scale - expand,
                        width: expand * 2,
                        height: expand * 2
                    )
                    rects.append(rect)
                }
            }
        }

        // Draw detected regions
        for rect in rects {
            drawView.drawMasks([rect])
        }
    }

    // MARK: - Inpaint

    @objc private func onInpaint() {
        guard let inputImage = imageView.image else { return }

        // Use selection overlay masks if available
        let selectionRects = selectionOverlay.selectionRects
        if !selectionRects.isEmpty {
            // Convert selection rects to mask
            let maskImage = createMaskImage(from: selectionRects, size: inputImage.size)
            performInpaint(with: inputImage, mask: maskImage)
        } else {
            // Use drawing mask (LaMa pipeline handles coordinate mapping internally)
            guard let maskImage = drawView.exportAsGrayscaleImage() else { return }
            performInpaint(with: inputImage, mask: maskImage)
        }
    }

    private func performInpaint(with inputImage: UIImage, mask: UIImage) {
        let bounds = drawView.drawBounds
        if !hasWarned, let rect = bounds.first, (rect.size.width > 512 || rect.size.height > 512) {
            hasWarned = true
            view.makeToast(*"toast_inpaint_warning", duration: 4.0, position: .bottom)
        }

        // Start simulated progress
        var simulatedProgress: Float = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            simulatedProgress += Float.random(in: 0.03...0.08)
            if simulatedProgress > 0.9 {
                simulatedProgress = 0.9
                timer.invalidate()
            }
            self?.processingOverlay.state = .progress(message: *"processing", value: simulatedProgress)
        }

        let options = ProcessingOptions()

        processor.process(
            input: ProcessingInput(image: inputImage),
            mask: mask,
            maskRects: bounds,
            options: options
        ) { [weak self] result in
            guard let self = self else { return }
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            self.hideProcessing()
            if let output = result.outputImage {
                self.pushUndo(inputImage)
                self.imageView.image = output
                // Keep mask cleared but stay in edit mode
                self.drawView.clean()
                self.selectionOverlay.clearSelections()
                self.updateUndoButtonState()
            } else if let error = result.error {
                self.view.makeToast(error.localizedDescription, duration: 3.0, position: .bottom)
            }
        }
    }

    private func createMaskImage(from rects: [CGRect], size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        UIColor.white.setFill()
        for rect in rects {
            UIRectFill(rect)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

}
