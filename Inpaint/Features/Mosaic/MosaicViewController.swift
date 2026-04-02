//
//  MosaicViewController.swift
//  Inpaint
//
//  Updated on 2026/03/31.
//

import UIKit
import SnapKit
import Toast_Swift

class MosaicViewController: BaseEditingViewController {

    override var toolID: String { "mosaic" }

    private let processor = MosaicProcessor()
    private var mosaicType: MosaicType = .pixelate
    private var mosaicIntensity: CGFloat = 20.0

    // MARK: - UI

    private lazy var drawView: SmudgeDrawingView = {
        let view = SmudgeDrawingView()
        view.smudgeColor = UIColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 0.4)
        return view
    }()

    private var brushSize: CGFloat = 20.0

    private lazy var brushSizeSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 10
        slider.maximumValue = 60
        let lastValue = UserDefaults.standard.object(forKey: "mosaicBrushSize") as? Float ?? 20
        slider.value = lastValue
        brushSize = CGFloat(lastValue)
        drawView.brushSize = brushSize
        slider.addTarget(self, action: #selector(brushSizeChanged(_:)), for: .valueChanged)
        return slider
    }()

    private lazy var intensitySlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 5
        slider.maximumValue = 50
        let lastValue = UserDefaults.standard.object(forKey: "mosaicIntensity") as? Float ?? 20
        slider.value = lastValue
        mosaicIntensity = CGFloat(lastValue)
        slider.addTarget(self, action: #selector(intensityChanged(_:)), for: .valueChanged)
        return slider
    }()

    private lazy var autoFaceButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(*"mosaic_auto_face", for: .normal)
        btn.setImage(UIImage(systemName: "person.fill.viewfinder"), for: .normal)
        btn.addTarget(self, action: #selector(onAutoFace), for: .touchUpInside)
        return btn
    }()

    // MARK: - Setup

    override func setupToolUI() {
        imageView.addSubview(drawView)
        drawView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 涂抹完成后自动应用马赛克
        drawView.onStrokeCompleted = { [weak self] in
            self?.applyMosaic()
        }

        setupBottomToolbar()
    }

    private func setupBottomToolbar() {
        let toolbar = UIToolbar()
        toolbar.isTranslucent = true

        // Type buttons
        let pixelateItem = UIBarButtonItem(title: *"mosaic_pixelate", style: .plain, target: self, action: #selector(selectPixelate))
        let blurItem = UIBarButtonItem(title: *"mosaic_blur", style: .plain, target: self, action: #selector(selectBlur))
        let crystalItem = UIBarButtonItem(title: *"mosaic_crystallize", style: .plain, target: self, action: #selector(selectCrystal))
        let triangleItem = UIBarButtonItem(title: *"mosaic_triangle", style: .plain, target: self, action: #selector(selectTriangle))

        // Brush size slider - use existing lazy property
        let brushSliderItem = UIBarButtonItem(customView: brushSizeSlider)
        brushSizeSlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

        // Brush size label
        let brushLabel = UILabel()
        brushLabel.text = *"brush_size"
        brushLabel.font = .systemFont(ofSize: 12)
        brushLabel.textColor = .secondaryLabel
        let brushLabelItem = UIBarButtonItem(customView: brushLabel)

        // Intensity slider - use existing lazy property
        let intensitySliderItem = UIBarButtonItem(customView: intensitySlider)
        intensitySlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

        // Intensity label
        let intensityLabel = UILabel()
        intensityLabel.text = *"mosaic_intensity"
        intensityLabel.font = .systemFont(ofSize: 12)
        intensityLabel.textColor = .secondaryLabel
        let intensityLabelItem = UIBarButtonItem(customView: intensityLabel)

        // Auto face button
        let faceBtn = UIButton(type: .system)
        faceBtn.setTitle(*"mosaic_auto_face", for: .normal)
        faceBtn.setImage(UIImage(systemName: "person.fill.viewfinder"), for: .normal)
        faceBtn.addTarget(self, action: #selector(onAutoFace), for: .touchUpInside)
        let faceItem = UIBarButtonItem(customView: faceBtn)

        let flex1 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let flex2 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let flex3 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [
            pixelateItem, blurItem, crystalItem, triangleItem,
            flex1, brushLabelItem, brushSliderItem, flex2,
            intensityLabelItem, intensitySliderItem, flex3, faceItem
        ]

        view.addSubview(toolbar)
        toolbar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(56)
        }

        scrollView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(toolbar.snp.top)
        }
    }

    override func setupNavigationItems() {
        undoButton.isEnabled = false
        let saveButton = UIBarButtonItem(title: *"save_to_photo_lib", style: .plain, target: self, action: #selector(onSave))
        navigationItem.rightBarButtonItems = [saveButton, undoButton]
    }

    // MARK: - Actions

    @objc private func selectPixelate() {
        mosaicType = .pixelate
        view.makeToast(*"mosaic_pixelate_selected", duration: 1.0, position: .bottom)
    }

    @objc private func selectBlur() {
        mosaicType = .gaussianBlur
        view.makeToast(*"mosaic_blur_selected", duration: 1.0, position: .bottom)
    }

    @objc private func selectCrystal() {
        mosaicType = .crystallize
        view.makeToast(*"mosaic_crystallize", duration: 1.0, position: .bottom)
    }

    @objc private func selectTriangle() {
        mosaicType = .trianglePixelate
        view.makeToast(*"mosaic_triangle", duration: 1.0, position: .bottom)
    }

    @objc private func brushSizeChanged(_ sender: UISlider) {
        let roundedValue = round(sender.value)
        brushSize = CGFloat(roundedValue)
        drawView.brushSize = brushSize
        UserDefaults.standard.set(roundedValue, forKey: "mosaicBrushSize")
    }

    @objc private func intensityChanged(_ sender: UISlider) {
        let roundedValue = round(sender.value)
        mosaicIntensity = CGFloat(roundedValue)
        UserDefaults.standard.set(roundedValue, forKey: "mosaicIntensity")
    }

    @objc private func onAutoFace() {
        guard let inputImage = imageView.image else { return }

        showProcessing(message: *"processing")

        Task {
            do {
                let normalizedBoxes = try await FaceDetectionHelper.detectFaces(in: inputImage)
                let imageSize = inputImage.size
                let rects = FaceDetectionHelper.faceMaskRects(
                    from: normalizedBoxes,
                    imageSize: imageSize,
                    padding: 0.25
                )

                await MainActor.run {
                    self.hideProcessing()
                    if rects.isEmpty {
                        self.view.makeToast(*"mosaic_no_faces", duration: 2.0, position: .bottom)
                    } else {
                        // Draw face masks and auto-apply mosaic
                        self.drawView.drawMasks(rects)
                        self.applyMosaic()
                        self.view.makeToast("\(*"mosaic_faces_detected") \(rects.count)", duration: 2.0, position: .bottom)
                    }
                }
            } catch {
                await MainActor.run {
                    self.hideProcessing()
                    self.view.makeToast(error.localizedDescription, duration: 3.0, position: .bottom)
                }
            }
        }
    }

    private func applyMosaic() {
        guard let inputImage = imageView.image else { return }
        guard let maskImage = drawView.exportAsGrayscaleImage(for: inputImage.size) else { return }

        let bounds = drawView.drawBounds
        guard !bounds.isEmpty else { return }

        showProcessing(message: *"processing")

        let options = ProcessingOptions([
            "mosaicType": mosaicType,
            "intensity": mosaicIntensity
        ])

        processor.process(
            input: ProcessingInput(image: inputImage),
            mask: maskImage,
            maskRects: bounds,
            options: options
        ) { [weak self] result in
            guard let self = self else { return }
            self.hideProcessing()
            if let output = result.outputImage {
                self.pushUndo(inputImage)
                self.imageView.image = output
                self.drawView.clean()
            } else if let error = result.error {
                self.view.makeToast(error.localizedDescription, duration: 3.0, position: .bottom)
            }
        }
    }
}
