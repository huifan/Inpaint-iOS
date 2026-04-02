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

    private let processor = MosaicProcessor()
    private var mosaicType: MosaicType = .pixelate
    private var mosaicIntensity: CGFloat = 20.0
    private weak var bottomToolbar: UIView?

    // MARK: - Init

    @MainActor override init(toolID: String) {
        super.init(toolID: toolID)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

    private lazy var typeSelector: UISegmentedControl = {
        let selector = UISegmentedControl(items: [
            *"mosaic_pixelate",
            *"mosaic_blur",
            *"mosaic_crystallize",
            *"mosaic_triangle"
        ])
        selector.selectedSegmentIndex = 0
        selector.addTarget(self, action: #selector(typeChanged(_:)), for: .valueChanged)
        return selector
    }()

    // MARK: - Setup

    override func setupToolUI() {
        if !isImageSelected {
            setupEmptyState(config: EmptyStateConfig(
                toolID: toolID,
                iconName: "square.grid.3x3",
                titleKey: "empty_mosaic_title",
                descriptionKey: "empty_mosaic_description",
                buttonTitleKey: "select_photo"
            ))
            return
        }

        setupMosaicUI()
    }

    private func setupMosaicUI() {
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
        bottomToolbar?.removeFromSuperview()
        let toolbar = UIView()
        toolbar.backgroundColor = .systemBackground
        bottomToolbar = toolbar

        let brushLabel = UILabel()
        brushLabel.text = *"brush_size"
        brushLabel.font = .systemFont(ofSize: 12)
        brushLabel.textColor = .secondaryLabel

        let intensityLabel = UILabel()
        intensityLabel.text = *"mosaic_intensity"
        intensityLabel.font = .systemFont(ofSize: 12)
        intensityLabel.textColor = .secondaryLabel

        let brushRow = UIStackView(arrangedSubviews: [brushLabel, brushSizeSlider])
        brushRow.axis = .horizontal
        brushRow.spacing = 12
        brushRow.alignment = .center

        let intensityRow = UIStackView(arrangedSubviews: [intensityLabel, intensitySlider])
        intensityRow.axis = .horizontal
        intensityRow.spacing = 12
        intensityRow.alignment = .center

        let contentStack = UIStackView(arrangedSubviews: [typeSelector, brushRow, intensityRow, autoFaceButton])
        contentStack.axis = .vertical
        contentStack.spacing = 10

        toolbar.addSubview(contentStack)
        view.addSubview(toolbar)

        brushLabel.setContentHuggingPriority(.required, for: .horizontal)
        intensityLabel.setContentHuggingPriority(.required, for: .horizontal)
        autoFaceButton.configuration = .bordered()

        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(12)
        }

        toolbar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(164)
        }

        scrollView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(toolbar.snp.top)
        }
    }

    override func setupNavigationItems() {
        setupUnifiedNavigationItems()

        compareButton = makeCompareButton()
        navigationItem.rightBarButtonItems = buildRightBarButtonItems(primaryItems: [undoButton])
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
        setupMosaicUI()
    }

    override func resetEditState() {
        super.resetEditState()
        drawView.clean()
        mosaicType = .pixelate
        mosaicIntensity = 20.0
    }

    // MARK: - Actions

    @objc private func typeChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            mosaicType = .pixelate
            view.makeToast(*"mosaic_pixelate_selected", duration: 1.0, position: .bottom)
        case 1:
            mosaicType = .gaussianBlur
            view.makeToast(*"mosaic_blur_selected", duration: 1.0, position: .bottom)
        case 2:
            mosaicType = .crystallize
            view.makeToast(*"mosaic_crystallize", duration: 1.0, position: .bottom)
        case 3:
            mosaicType = .trianglePixelate
            view.makeToast(*"mosaic_triangle", duration: 1.0, position: .bottom)
        default:
            break
        }
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
                        // Convert image-space face rects into the overlay's view-space before drawing.
                        let displayRects = rects.compactMap { self.convertImageRectToDrawView($0, imageSize: imageSize) }
                        guard !displayRects.isEmpty else {
                            self.view.makeToast(*"mosaic_no_faces", duration: 2.0, position: .bottom)
                            return
                        }

                        // Draw face masks and auto-apply mosaic
                        self.drawView.drawFilledMasks(displayRects)
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

    private func convertImageRectToDrawView(_ rect: CGRect, imageSize: CGSize) -> CGRect? {
        let viewSize = drawView.bounds.size
        guard viewSize.width > 0, viewSize.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        let displayRect: CGRect
        if imageAspect > viewAspect {
            let displayWidth = viewSize.width
            let displayHeight = viewSize.width / imageAspect
            let yOffset = (viewSize.height - displayHeight) / 2.0
            displayRect = CGRect(x: 0, y: yOffset, width: displayWidth, height: displayHeight)
        } else {
            let displayHeight = viewSize.height
            let displayWidth = viewSize.height * imageAspect
            let xOffset = (viewSize.width - displayWidth) / 2.0
            displayRect = CGRect(x: xOffset, y: 0, width: displayWidth, height: displayHeight)
        }

        let scaleX = displayRect.width / imageSize.width
        let scaleY = displayRect.height / imageSize.height

        return CGRect(
            x: displayRect.origin.x + rect.origin.x * scaleX,
            y: displayRect.origin.y + rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).intersection(CGRect(origin: .zero, size: viewSize))
    }
}
