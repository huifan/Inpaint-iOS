//
//  TextRemovalViewController.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit
import Toast_Swift

class TextRemovalViewController: BaseEditingViewController {

    private let processor = TextRemovalProcessor()
    private var detectedTextRects: [CGRect] = []
    private var selectedRects: Set<Int> = []
    private var textOverlayViews: [TextRegionView] = []

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

    private lazy var textOverlayView: PassthroughView = {
        let view = PassthroughView()
        view.isUserInteractionEnabled = true
        return view
    }()

    /// Tracks whether a removal has been performed (to prevent repeated detect+remove)
    private var hasPerformedRemoval = false

    private lazy var detectButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(*"text_detect", for: .normal)
        btn.setImage(UIImage(systemName: "text.magnifyingglass"), for: .normal)
        btn.addTarget(self, action: #selector(onDetectText), for: .touchUpInside)
        return btn
    }()

    private lazy var selectAllButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(*"text_select_all", for: .normal)
        btn.addTarget(self, action: #selector(onSelectAll), for: .touchUpInside)
        return btn
    }()

    private lazy var deselectAllButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(*"text_deselect_all", for: .normal)
        btn.addTarget(self, action: #selector(onDeselectAll), for: .touchUpInside)
        return btn
    }()

    // MARK: - Setup

    override func setupToolUI() {
        if !isImageSelected {
            setupEmptyState(config: EmptyStateConfig(
                toolID: toolID,
                iconName: "text.magnifyingglass",
                titleKey: "empty_text_removal_title",
                descriptionKey: "empty_text_removal_description",
                buttonTitleKey: "select_photo"
            ))
            return
        }

        setupTextRemovalUI()
    }

    private func setupTextRemovalUI() {
        processor.preload()

        imageView.addSubview(drawView)
        drawView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // textOverlayView on top so taps reach TextRegionViews;
        // PassthroughView forwards non-hit touches to drawView below.
        imageView.addSubview(textOverlayView)
        textOverlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        drawView.onStrokeCompleted = { [weak self] in
            self?.updateUndoButtonState()
        }

        setupBottomToolbar()
    }

    private func setupBottomToolbar() {
        let toolbar = UIToolbar()
        toolbar.isTranslucent = true

        let detectItem = UIBarButtonItem(customView: detectButton)
        let selectAllItem = UIBarButtonItem(customView: selectAllButton)
        let deselectAllItem = UIBarButtonItem(customView: deselectAllButton)
        let flex1 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let flex2 = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [
            detectItem, flex1, selectAllItem, deselectAllItem, flex2
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
        setupUnifiedNavigationItems()

        let removeButton = UIBarButtonItem(title: *"text_remove", style: .done, target: self, action: #selector(onRemove))
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
        setupTextRemovalUI()
        // Auto-detect text on entry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.onDetectText()
        }
    }

    override func resetEditState() {
        super.resetEditState()
        detectedTextRects.removeAll()
        selectedRects.removeAll()
        for view in textOverlayViews {
            view.removeFromSuperview()
        }
        textOverlayViews.removeAll()
        hasPerformedRemoval = false
        drawView.clean()
    }

    // MARK: - Actions

    @objc private func onDetectText() {
        guard !hasPerformedRemoval else {
            view.makeToast(*"text_already_removed", duration: 2.0, position: .bottom)
            return
        }
        showProcessing(message: *"processing")

        Task {
            do {
                guard let img = originalImage else { return }
                let normalizedImage = img.normalizedOrientation()
                let rects = try await processor.detectText(in: normalizedImage)

                await MainActor.run {
                    self.hideProcessing()
                    self.detectedTextRects = rects
                    self.updateTextOverlays()

                    if rects.isEmpty {
                        self.view.makeToast(*"text_no_text_found", duration: 2.0, position: .bottom)
                    } else {
                        self.view.makeToast(String(format: *"text_detected_count", rects.count), duration: 2.0, position: .bottom)
                        // Auto-select all detected regions
                        self.selectAllRects()
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

    @objc private func onSelectAll() {
        selectAllRects()
    }

    @objc private func onDeselectAll() {
        selectedRects.removeAll()
        updateTextOverlays()
    }

    private func selectAllRects() {
        selectedRects.removeAll()
        for i in 0..<detectedTextRects.count {
            selectedRects.insert(i)
        }
        updateTextOverlays()
    }

    private func updateTextOverlays() {
        // Remove existing overlay views
        textOverlayViews.forEach { $0.removeFromSuperview() }
        textOverlayViews.removeAll()

        guard let img = originalImage else { return }

        // Calculate offset for aspect-fit image
        let imageSize = img.size
        let viewSize = imageView.bounds.size
        let aspectFitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * aspectFitScale) / 2
        let offsetY = (viewSize.height - imageSize.height * aspectFitScale) / 2

        // Create new overlay views
        for (index, rect) in detectedTextRects.enumerated() {
            let isSelected = selectedRects.contains(index)

            // Convert rect from image coordinates to view coordinates
            let scaledRect = CGRect(
                x: rect.origin.x * aspectFitScale + offsetX,
                y: rect.origin.y * aspectFitScale + offsetY,
                width: rect.width * aspectFitScale,
                height: rect.height * aspectFitScale
            )

            let overlay = TextRegionView(frame: scaledRect, isSelected: isSelected)
            overlay.onTap = { [weak self] in
                self?.toggleRect(at: index)
            }

            textOverlayView.addSubview(overlay)
            textOverlayViews.append(overlay)
        }
    }

    private func toggleRect(at index: Int) {
        if selectedRects.contains(index) {
            selectedRects.remove(index)
        } else {
            selectedRects.insert(index)
        }
        updateTextOverlays()
    }

    override func onUndo() {
        super.onUndo()
        hasPerformedRemoval = false
        detectButton.isEnabled = true
    }

    private func updateUndoButtonState() {
        undoButton.isEnabled = drawView.hasStrokes || canUndo
    }

    @objc private func onRemove() {
        guard let inputImage = imageView.image else { return }
        let imageSize = inputImage.size
        let imageBounds = CGRect(origin: .zero, size: imageSize)

        // 1. Collect selected text rects with padding (in image coordinates)
        var textRects: [CGRect] = []
        for index in selectedRects {
            let rect = detectedTextRects[index]
            // Expand 20% to cover edge pixels of text that Vision's tight bbox misses
            let padX = rect.width * 0.2
            let padY = rect.height * 0.2
            let expanded = rect.insetBy(dx: -padX, dy: -padY).intersection(imageBounds)
            textRects.append(expanded)
        }

        // 2. Convert drawn bounds from view*scale coords to image coordinates
        var drawnImageRects: [CGRect] = []
        let hasDrawn = drawView.hasStrokes
        if hasDrawn {
            let viewSize = drawView.bounds.size
            let fitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
            let offsetX = (viewSize.width - imageSize.width * fitScale) / 2
            let offsetY = (viewSize.height - imageSize.height * fitScale) / 2

            for rawRect in drawView.drawBounds {
                // drawBounds multiplies by UIScreen.main.scale — undo that
                let viewRect = rawRect / UIScreen.main.scale
                let imageRect = CGRect(
                    x: (viewRect.origin.x - offsetX) / fitScale,
                    y: (viewRect.origin.y - offsetY) / fitScale,
                    width: viewRect.width / fitScale,
                    height: viewRect.height / fitScale
                ).intersection(imageBounds)
                drawnImageRects.append(imageRect)
            }
        }

        let allCropRects = textRects + drawnImageRects
        guard !allCropRects.isEmpty else {
            view.makeToast(*"text_no_region_selected", duration: 2.0, position: .bottom)
            return
        }

        showProcessing(message: *"processing")

        // 3. Build mask: text rects as filled rectangles + actual drawn paths
        let maskImage = createCombinedMask(textRects: textRects, hasDrawn: hasDrawn, imageSize: imageSize)

        // 4. Cluster nearby rects so each cluster is processed independently at higher resolution.
        //    Without clustering, all rects merge into one giant bounding box → the entire image
        //    is downscaled to 512×512, causing severe blurriness on text-heavy images.
        let clusters = Self.clusterRects(allCropRects, threshold: 100)

        processor.processIteratively(
            input: ProcessingInput(image: inputImage),
            mask: maskImage,
            clusters: clusters,
            progress: { [weak self] value in
                self?.processingOverlay.state = .progress(message: *"processing", value: value)
            }
        ) { [weak self] result in
            guard let self = self else { return }
            self.hideProcessing()
            if let output = result.outputImage {
                self.pushUndo(inputImage)
                self.imageView.image = output
                self.drawView.clean()
                self.selectedRects.removeAll()
                self.detectedTextRects.removeAll()
                self.textOverlayViews.forEach { $0.removeFromSuperview() }
                self.textOverlayViews.removeAll()
                self.hasPerformedRemoval = true
                self.detectButton.isEnabled = false
                self.view.makeToast(*"text_removed", duration: 2.0, position: .bottom)
            } else if let error = result.error {
                self.view.makeToast(error.localizedDescription, duration: 3.0, position: .bottom)
            }
        }
    }

    /// Group nearby rects into clusters. Each cluster will be processed as one LaMa pass.
    /// Rects whose expanded bounds overlap are merged into the same cluster.
    static func clusterRects(_ rects: [CGRect], threshold: CGFloat) -> [[CGRect]] {
        var clusters: [[CGRect]] = rects.map { [$0] }
        var merged = true

        while merged {
            merged = false
            for i in 0..<clusters.count {
                let boundsI = clusters[i].largestBoundingRect().insetBy(dx: -threshold, dy: -threshold)
                for j in (i + 1)..<clusters.count {
                    if boundsI.intersects(clusters[j].largestBoundingRect()) {
                        clusters[i].append(contentsOf: clusters[j])
                        clusters.remove(at: j)
                        merged = true
                        break
                    }
                }
                if merged { break }
            }
        }

        return clusters
    }

    /// Build a combined mask: filled rects for text regions + actual drawn paths for manual regions.
    /// Using drawn paths instead of bounding rects prevents the model from reconstructing large unnecessary areas.
    private func createCombinedMask(textRects: [CGRect], hasDrawn: Bool, imageSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: imageSize))

        // Text detection regions — fill rectangles
        UIColor.white.setFill()
        for rect in textRects {
            UIRectFill(rect)
        }

        // Manual drawn regions — use actual path mask (not bounding rect) for precision
        if hasDrawn, let drawnMask = drawView.exportAsGrayscaleImage(for: imageSize) {
            drawnMask.draw(in: CGRect(origin: .zero, size: imageSize), blendMode: .screen, alpha: 1.0)
        }

        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}

// MARK: - Passthrough View

/// A view that only captures touches on its subviews; taps on empty area pass through to views below.
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

// MARK: - Text Region View

final class TextRegionView: UIView {
    var onTap: (() -> Void)?
    private let isSelected: Bool

    init(frame: CGRect, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = isSelected ?
            UIColor.systemBlue.withAlphaComponent(0.3) :
            UIColor.systemRed.withAlphaComponent(0.3)
        layer.borderColor = isSelected ?
            UIColor.systemBlue.cgColor :
            UIColor.systemRed.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 4

        let tap = UITapGestureRecognizer(target: self, action: #selector(onTapGesture))
        addGestureRecognizer(tap)
    }

    @objc private func onTapGesture() {
        onTap?()
    }
}
