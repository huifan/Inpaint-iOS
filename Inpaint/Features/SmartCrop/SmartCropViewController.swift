//
//  SmartCropViewController.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit
import Toast_Swift

class SmartCropViewController: BaseEditingViewController {

    override var toolID: String { "smart_crop" }

    private let processor = SmartCropProcessor()

    enum AspectRatio: CaseIterable {
        case free
        case square       // 1:1
        case ratio4x3    // 4:3
        case ratio16x9    // 16:9
        case ratio9x16   // 9:16

        var value: CGFloat? {
            switch self {
            case .free: return nil
            case .square: return 1.0
            case .ratio4x3: return 4.0 / 3.0
            case .ratio16x9: return 16.0 / 9.0
            case .ratio9x16: return 9.0 / 16.0
            }
        }

        var displayNameKey: String {
            switch self {
            case .free: return "crop_free"
            case .square: return "1:1"
            case .ratio4x3: return "4:3"
            case .ratio16x9: return "16:9"
            case .ratio9x16: return "9:16"
            }
        }
    }

    private var currentRatio: AspectRatio = .free
    private var cropOverlay: CropOverlayView?
    private var initialCropRect: CGRect = .zero

    // MARK: - UI

    private lazy var ratioButtons: [UIButton] = {
        return AspectRatio.allCases.map { ratio in
            let btn = UIButton(type: .system)
            btn.setTitle(*ratio.displayNameKey, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13)
            btn.tag = AspectRatio.allCases.firstIndex(of: ratio) ?? 0
            btn.addTarget(self, action: #selector(ratioButtonTapped(_:)), for: .touchUpInside)
            return btn
        }
    }()

    private lazy var smartButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(*"crop_smart", for: .normal)
        btn.setImage(UIImage(systemName: "wand.and.stars"), for: .normal)
        btn.addTarget(self, action: #selector(onSmartCrop), for: .touchUpInside)
        return btn
    }()

    // MARK: - Setup

    override func setupToolUI() {
        // Disable zoom for crop
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 1.0

        setupCropOverlay()
        setupBottomToolbar()
    }

    private func setupCropOverlay() {
        let viewSize = imageView.bounds.size
        let imageSize = originalImage.size

        // Calculate initial crop rect (with padding)
        let padding: CGFloat = 0.1
        let aspectFitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledImageSize = CGSize(
            width: imageSize.width * aspectFitScale,
            height: imageSize.height * aspectFitScale
        )
        let offsetX = (viewSize.width - scaledImageSize.width) / 2
        let offsetY = (viewSize.height - scaledImageSize.height) / 2

        initialCropRect = CGRect(
            x: offsetX + scaledImageSize.width * padding,
            y: offsetY + scaledImageSize.height * padding,
            width: scaledImageSize.width * (1 - 2 * padding),
            height: scaledImageSize.height * (1 - 2 * padding)
        )

        let overlay = CropOverlayView(cropRect: initialCropRect)
        overlay.delegate = self
        overlay.aspectRatio = currentRatio.value
        overlay.isHidden = true
        imageView.addSubview(overlay)
        cropOverlay = overlay
    }

    private func setupBottomToolbar() {
        let toolbar = UIToolbar()
        toolbar.isTranslucent = true

        var items: [UIBarButtonItem] = []

        for (index, button) in ratioButtons.enumerated() {
            let item = UIBarButtonItem(customView: button)
            items.append(item)
            if index < ratioButtons.count - 1 {
                items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            }
        }

        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        items.append(UIBarButtonItem(customView: smartButton))

        toolbar.items = items

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
        let backButton = UIBarButtonItem(title: *"back", style: .plain, target: self, action: #selector(onBack))
        let cropButton = UIBarButtonItem(title: *"crop_done", style: .done, target: self, action: #selector(onCrop))
        compareButton = makeCompareButton()

        navigationItem.leftBarButtonItems = [backButton]
        navigationItem.rightBarButtonItems = [compareButton!, cropButton]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Show crop overlay when view appears
        cropOverlay?.isHidden = false
        updateRatioButtonStates()
    }

    // MARK: - Actions

    @objc private func onBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func ratioButtonTapped(_ sender: UIButton) {
        let ratio = AspectRatio.allCases[sender.tag]
        currentRatio = ratio
        cropOverlay?.aspectRatio = ratio.value

        // If switching to a fixed ratio, adjust current crop rect
        guard let newRatio = ratio.value, let currentOverlay = cropOverlay else { return }

        var newCropRect = currentOverlay.cropRect

        // Adjust to maintain the new ratio
        let centerX = newCropRect.midX
        let centerY = newCropRect.midY

        if newCropRect.width / newCropRect.height > newRatio {
            // Width is too large, adjust width
            newCropRect.size.width = newCropRect.height * newRatio
        } else {
            // Height is too large, adjust height
            newCropRect.size.height = newCropRect.width / newRatio
        }

        newCropRect.origin.x = centerX - newCropRect.width / 2
        newCropRect.origin.y = centerY - newCropRect.height / 2

        currentOverlay.setCropRect(newCropRect, animated: true)
        updateRatioButtonStates()
    }

    @objc private func onSmartCrop() {
        showProcessing(message: *"processing")

        Task {
            do {
                // Try to detect faces first
                let faces = try await processor.detectFaces(in: originalImage)

                await MainActor.run {
                    if !faces.isEmpty {
                        // Use face detection result
                        self.applyCropForFaces(faces)
                    } else {
                        // Fall back to saliency detection
                        self.applySaliencyCrop()
                    }
                }
            } catch {
                // Fall back to saliency
                await MainActor.run {
                    self.applySaliencyCrop()
                }
            }
        }
    }

    private func applyCropForFaces(_ faces: [CGRect]) {
        hideProcessing()

        // Calculate bounding rect that contains all faces
        var unionRect = faces[0]
        for face in faces.dropFirst() {
            unionRect = unionRect.union(face)
        }

        // Add padding around faces
        let padding: CGFloat = 0.3
        let expandedRect = unionRect.insetBy(dx: -unionRect.width * padding, dy: -unionRect.height * padding)

        // Convert to view coordinates
        let viewCropRect = cropRectForImageRect(expandedRect, imageSize: originalImage.size, viewSize: imageView.bounds.size)

        // Apply aspect ratio constraint
        var finalRect = viewCropRect
        if let ratio = currentRatio.value {
            let centerX = finalRect.midX
            let centerY = finalRect.midY

            if finalRect.width / finalRect.height > ratio {
                finalRect.size.width = finalRect.height * ratio
            } else {
                finalRect.size.height = finalRect.width / ratio
            }

            finalRect.origin.x = centerX - finalRect.width / 2
            finalRect.origin.y = centerY - finalRect.height / 2
        }

        // Ensure within bounds
        finalRect = finalRect.intersection(CGRect(origin: .zero, size: imageView.bounds.size))

        cropOverlay?.setCropRect(finalRect, animated: true)
        view.makeToast(*"crop_face_detected", duration: 2.0, position: .bottom)
    }

    private func applySaliencyCrop() {
        hideProcessing()

        // Default to a centered crop with padding
        let padding: CGFloat = 0.15
        let imageSize = originalImage.size
        let aspectFitScale = min(imageView.bounds.width / imageSize.width, imageView.bounds.height / imageSize.height)
        let scaledImageSize = CGSize(
            width: imageSize.width * aspectFitScale,
            height: imageSize.height * aspectFitScale
        )
        let offsetX = (imageView.bounds.width - scaledImageSize.width) / 2
        let offsetY = (imageView.bounds.height - scaledImageSize.height) / 2

        var viewCropRect = CGRect(
            x: offsetX + scaledImageSize.width * padding,
            y: offsetY + scaledImageSize.height * padding,
            width: scaledImageSize.width * (1 - 2 * padding),
            height: scaledImageSize.height * (1 - 2 * padding)
        )

        // Apply aspect ratio constraint
        if let ratio = currentRatio.value {
            let centerX = viewCropRect.midX
            let centerY = viewCropRect.midY

            if viewCropRect.width / viewCropRect.height > ratio {
                viewCropRect.size.width = viewCropRect.height * ratio
            } else {
                viewCropRect.size.height = viewCropRect.width / ratio
            }

            viewCropRect.origin.x = centerX - viewCropRect.width / 2
            viewCropRect.origin.y = centerY - viewCropRect.height / 2
        }

        cropOverlay?.setCropRect(viewCropRect, animated: true)
        view.makeToast(*"crop_smart_applied", duration: 2.0, position: .bottom)
    }

    private func cropRectForImageRect(_ imageRect: CGRect, imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let aspectFitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * aspectFitScale) / 2
        let offsetY = (viewSize.height - imageSize.height * aspectFitScale) / 2

        return CGRect(
            x: imageRect.origin.x * aspectFitScale + offsetX,
            y: imageRect.origin.y * aspectFitScale + offsetY,
            width: imageRect.width * aspectFitScale,
            height: imageRect.height * aspectFitScale
        )
    }

    @objc private func onCrop() {
        guard let overlay = cropOverlay else { return }

        let imageCropRect = overlay.cropRectInImageCoordinates(
            imageSize: originalImage.size,
            viewSize: imageView.bounds.size
        )

        pushUndo(originalImage)

        let options = ProcessingOptions(["cropRect": imageCropRect])

        processor.process(
            input: ProcessingInput(image: originalImage),
            options: options
        ) { [weak self] result in
            guard let self = self else { return }
            if let output = result.outputImage {
                self.imageView.image = output
                overlay.isHidden = true
                self.view.makeToast(*"crop_applied", duration: 2.0, position: .bottom)
            } else if let error = result.error {
                self.view.makeToast(error.localizedDescription, duration: 3.0, position: .bottom)
            }
        }
    }

    private func updateRatioButtonStates() {
        for (index, button) in ratioButtons.enumerated() {
            let isSelected = AspectRatio.allCases[index] == currentRatio
            button.tintColor = isSelected ? .systemBlue : .label
            button.backgroundColor = isSelected ? .systemBlue.withAlphaComponent(0.1) : .clear
            button.layer.cornerRadius = 8
        }
    }
}

// MARK: - CropOverlayViewDelegate

extension SmartCropViewController: CropOverlayViewDelegate {
    func cropOverlayView(_ view: CropOverlayView, didUpdateCropRect cropRect: CGRect) {
        // Crop rect updated - could enable/disable apply button
    }
}
