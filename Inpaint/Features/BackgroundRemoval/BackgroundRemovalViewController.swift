//
//  BackgroundRemovalViewController.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit
import Toast_Swift

class BackgroundRemovalViewController: BaseEditingViewController {

    private let processor = BackgroundRemovalProcessor()
    private var backgroundMode: BackgroundMode = .transparent
    private var imagePicker: ImagePickerService?

    // MARK: - Init

    @MainActor override init(toolID: String) {
        super.init(toolID: toolID)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI

    private lazy var checkerboardView: CheckerboardView = {
        let view = CheckerboardView()
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var modeSelector: UISegmentedControl = {
        let items = [
            *"bg_transparent",
            *"bg_solid_color",
            *"bg_blur",
            *"bg_custom"
        ]
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        // 允许重复点击"自定义"重新选择背景图片
        let tap = UITapGestureRecognizer(target: self, action: #selector(onSegmentTapped(_:)))
        sc.addGestureRecognizer(tap)
        return sc
    }()

    // MARK: - Setup

    override func setupToolUI() {
        if !isImageSelected {
            setupEmptyState(config: EmptyStateConfig(
                toolID: toolID,
                iconName: "person.crop.rectangle",
                titleKey: "empty_bg_removal_title",
                descriptionKey: "empty_bg_removal_description",
                buttonTitleKey: "select_photo"
            ))
            return
        }

        setupBackgroundRemovalUI()
    }

    private func setupBackgroundRemovalUI() {
        // Checkerboard behind imageView to show transparency
        imageView.superview?.insertSubview(checkerboardView, belowSubview: imageView)
        checkerboardView.snp.makeConstraints { make in
            make.edges.equalTo(imageView)
        }

        // Bottom toolbar with mode selector
        let toolbar = UIView()
        toolbar.backgroundColor = .systemBackground
        view.addSubview(toolbar)
        toolbar.addSubview(modeSelector)

        toolbar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(56)
        }
        modeSelector.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }

        scrollView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(toolbar.snp.top)
        }
    }

    override func setupNavigationItems() {
        setupUnifiedNavigationItems()

        let removeButton = UIBarButtonItem(
            title: *"remove_background",
            style: .done, target: self,
            action: #selector(onRemoveBackground)
        )
        compareButton = makeCompareButton()
        navigationItem.rightBarButtonItems = buildRightBarButtonItems(primaryItems: [removeButton, undoButton])
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
        setupBackgroundRemovalUI()
    }

    override func resetEditState() {
        super.resetEditState()
        backgroundMode = .transparent
        modeSelector.selectedSegmentIndex = 0
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            backgroundMode = .transparent
        case 1:
            showColorPicker()
        case 2:
            backgroundMode = .blurred(radius: 20.0)
        case 3:
            pickCustomBackground()
        default:
            break
        }
    }

    private var pendingColorSelection = false

    private func showColorPicker() {
        let colorPicker = UIColorPickerViewController()
        colorPicker.selectedColor = .white
        colorPicker.supportsAlpha = false
        colorPicker.delegate = self
        present(colorPicker, animated: true)
    }

    @objc private func onRemoveBackground() {
        guard let inputImage = imageView.image else { return }

        if #unavailable(iOS 17.0) {
            view.makeToast(*"error_ios17_required", duration: 3.0, position: .bottom)
            return
        }

        showProcessing(message: *"processing_background_removal")

        let options = ProcessingOptions(["backgroundMode": backgroundMode])

        processor.process(input: ProcessingInput(image: inputImage), options: options) {
            [weak self] result in
            guard let self else { return }
            self.hideProcessing()
            if let output = result.outputImage {
                self.pushUndo(inputImage)
                self.imageView.image = output
            } else if let error = result.error {
                self.view.makeToast(error.localizedDescription, duration: 3.0, position: .bottom)
            }
        }
    }

    @objc private func onSegmentTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: modeSelector)
        // 检测点击的是否是"自定义"（最后一个 segment）
        let segmentWidth = modeSelector.bounds.width / CGFloat(modeSelector.numberOfSegments)
        let tappedIndex = Int(point.x / segmentWidth)
        if tappedIndex == 3 && modeSelector.selectedSegmentIndex == 3 {
            pickCustomBackground()
        }
    }

    private func pickCustomBackground() {
        let picker = ImagePickerService()
        imagePicker = picker
        picker.pickImage(from: self) { [weak self] image in
            guard let self else { return }
            self.imagePicker = nil
            guard let image else { return }
            self.backgroundMode = .customImage(image)
        }
    }

    // MARK: - Save

    @objc override func onSave() {
        guard let image = imageView.image else { return }
        ExportService.saveAsPNG(image) { [weak self] success, error in
            guard let self else { return }
            if success {
                self.view.makeToast(*"toast_save_success", duration: 2.0, position: .bottom)
            } else {
                self.view.makeToast("\(*"toast_save_error") \(error?.localizedDescription ?? "")", duration: 3.0, position: .bottom)
            }
        }
    }
}

// MARK: - UIColorPickerViewControllerDelegate

extension BackgroundRemovalViewController: UIColorPickerViewControllerDelegate {
    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        backgroundMode = .solidColor(color)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        // Color has been selected via didSelect
    }
}

// MARK: - Checkerboard View

/// A view that displays a checkerboard pattern to indicate transparency
final class CheckerboardView: UIView {

    private let squareSize: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        contentMode = .redraw
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let cols = Int(ceil(rect.width / squareSize))
        let rows = Int(ceil(rect.height / squareSize))

        for row in 0..<rows {
            for col in 0..<cols {
                let isLight = (row + col) % 2 == 0
                context.setFillColor(isLight ? UIColor(white: 0.95, alpha: 1.0).cgColor : UIColor(white: 0.85, alpha: 1.0).cgColor)
                context.fill(CGRect(
                    x: CGFloat(col) * squareSize,
                    y: CGFloat(row) * squareSize,
                    width: squareSize,
                    height: squareSize
                ))
            }
        }
    }
}
