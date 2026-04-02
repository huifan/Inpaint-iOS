//
//  BaseEditingViewController.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit
import SnapKit
import Toast_Swift

// MARK: - Empty State Models

enum EmptyStateImageSource {
    case photoLibrary
    case camera
    case clipboard
}

struct EmptyStateConfig {
    let toolID: String
    let iconName: String
    let titleKey: String
    let descriptionKey: String
    let buttonTitleKey: String
    let primaryImageSource: EmptyStateImageSource = .photoLibrary
}

protocol EmptyStateViewDelegate: AnyObject {
    func emptyStateViewDidTapSelectPhoto(_ view: EmptyStateView)
    func emptyStateView(_ view: EmptyStateView, didSelectImageSource source: EmptyStateImageSource)
}

final class EmptyStateView: UIView {

    weak var delegate: EmptyStateViewDelegate?

    private var config: EmptyStateConfig?

    private lazy var scrollContainerView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private lazy var containerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        return stack
    }()

    private lazy var iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemGray2
        return iv
    }()

    private lazy var dashedBorderView: DashedBorderView = {
        let view = DashedBorderView()
        view.onTap = { [weak self] in
            guard let self else { return }
            self.delegate?.emptyStateViewDidTapSelectPhoto(self)
        }
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var selectPhotoButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "photo.badge.plus"), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        btn.addTarget(self, action: #selector(onSelectPhoto), for: .touchUpInside)
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .systemBackground

        addSubview(scrollContainerView)
        scrollContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        scrollContainerView.addSubview(containerStack)
        containerStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(60)
            make.leading.trailing.equalTo(self).inset(40)
            make.bottom.equalToSuperview().offset(-60)
            make.width.equalTo(scrollContainerView).offset(-80)
        }

        containerStack.addArrangedSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.width.height.equalTo(64)
        }

        containerStack.addArrangedSubview(dashedBorderView)
        dashedBorderView.snp.makeConstraints { make in
            make.width.height.equalTo(200)
        }

        containerStack.addArrangedSubview(titleLabel)
        containerStack.setCustomSpacing(12, after: titleLabel)

        containerStack.addArrangedSubview(descriptionLabel)
        containerStack.setCustomSpacing(24, after: descriptionLabel)

        containerStack.addArrangedSubview(selectPhotoButton)
        selectPhotoButton.snp.makeConstraints { make in
            make.height.equalTo(50)
            make.width.equalTo(200)
        }
    }

    func configure(with config: EmptyStateConfig) {
        self.config = config

        iconImageView.image = UIImage(systemName: config.iconName)
        titleLabel.text = *config.titleKey
        descriptionLabel.text = *config.descriptionKey
        selectPhotoButton.setTitle(*config.buttonTitleKey, for: .normal)

        dashedBorderView.configure(
            iconName: config.iconName,
            placeholderKey: config.buttonTitleKey
        )
    }

    @objc private func onSelectPhoto() {
        guard let config else { return }
        delegate?.emptyStateView(self, didSelectImageSource: config.primaryImageSource)
    }
}

final class DashedBorderView: UIView {

    var onTap: (() -> Void)?

    private lazy var plusImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemGray2
        iv.image = UIImage(systemName: "photo.badge.plus")
        return iv
    }()

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .systemGray
        label.textAlignment = .center
        return label
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [plusImageView, placeholderLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }()

    private let dashPattern: [NSNumber] = [8, 4]
    private let shapeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .systemGray6
        layer.cornerRadius = 16

        shapeLayer.strokeColor = UIColor.systemGray3.cgColor
        shapeLayer.lineDashPattern = dashPattern
        shapeLayer.fillColor = nil
        shapeLayer.lineWidth = 2
        layer.mask = shapeLayer

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true

        addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        plusImageView.snp.makeConstraints { make in
            make.width.height.equalTo(48)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insetRect = bounds.insetBy(dx: 4, dy: 4)
        shapeLayer.path = UIBezierPath(roundedRect: insetRect, cornerRadius: 12).cgPath
    }

    func configure(iconName: String, placeholderKey: String) {
        placeholderLabel.text = *placeholderKey
    }

    @objc private func handleTap() {
        onTap?()
    }
}

// MARK: - Base Editing View Controller

class BaseEditingViewController: UIViewController {

    // MARK: - Properties

    let toolID: String

    init(toolID: String) {
        self.toolID = toolID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private(set) var originalImage: UIImage?
    private(set) var isImageSelected: Bool = false
    private var hasPendingImageSetup = false

    var emptyStateView: EmptyStateView?
    var replaceImageButton: UIBarButtonItem?
    var compareButton: UIBarButtonItem? {
        didSet { refreshOverflowMenu() }
    }
    private var overflowMenuButton: UIBarButtonItem?
    private let imagePickerService = ImagePickerService()

    lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.delegate = self
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 6.0
        return sv
    }()

    let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        return iv
    }()

    let processingOverlay = ProcessingOverlay()

    // MARK: - Undo

    private(set) var undoStack: [UIImage] = []

    var canUndo: Bool { !undoStack.isEmpty }

    var hasUnsavedChanges: Bool { !undoStack.isEmpty }

    lazy var undoButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain,
            target: self,
            action: #selector(onUndo)
        )
        button.accessibilityLabel = *"undo"
        return button
    }()

    // MARK: - Image Management

    func setImage(_ image: UIImage) {
        self.originalImage = image
        self.isImageSelected = true
        self.imageView.image = image
        self.hasPendingImageSetup = !isViewLoaded

        emptyStateView?.isHidden = true
        scrollView.isHidden = false
        replaceImageButton?.isEnabled = true
        refreshOverflowMenu()

        guard isViewLoaded else { return }
        didSetImage()
    }

    func didSetImage() {
        // Override in subclasses to perform setup after image is set
    }

    func setupEmptyState(config: EmptyStateConfig) {
        let view = EmptyStateView()
        view.configure(with: config)
        view.delegate = self
        view.isHidden = false
        self.emptyStateView = view
        self.view.addSubview(view)
        view.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.bottom.equalTo(self.view.safeAreaLayoutGuide)
        }
    }

    func presentImagePicker() {
        // Override in subclasses to present image picker
    }

    func pickImageFromLibrary(_ completion: @escaping (UIImage) -> Void) {
        imagePickerService.pickImage(from: self) { image in
            guard let image else { return }
            completion(image)
        }
    }

    func replaceImage() {
        imagePickerService.pickImage(from: self) { [weak self] image in
            guard let self, let image else { return }
            let scaledImage = image.scaleToLimit(size: CGSize(width: kLimitImageSize, height: kLimitImageSize))
            self.resetEditState()
            self.setImage(scaledImage)
        }
    }

    func resetEditState() {
        undoStack.removeAll()
        undoButton.isEnabled = false
        compareButton?.isEnabled = false
        refreshOverflowMenu()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setupBaseUI()
        if isImageSelected, hasPendingImageSetup {
            scrollView.isHidden = false
            didSetImage()
            hasPendingImageSetup = false
        } else {
            setupToolUI()
        }
        setupNavigationItems()
    }

    // MARK: - Base UI Setup

    private func setupBaseUI() {
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.bottom.equalTo(view.safeAreaLayoutGuide)
        }
        scrollView.isHidden = true

        scrollView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.width.height.equalToSuperview()
        }

        view.addSubview(processingOverlay)
        processingOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    /// Override in subclasses to add tool-specific UI (drawing view, sliders, etc.)
    func setupToolUI() {}

    /// Override in subclasses to customize navigation items
    func setupNavigationItems() {
        setupUnifiedNavigationItems()
    }

    // MARK: - Unified Navigation

    func setupUnifiedNavigationItems() {
        undoButton.isEnabled = false

        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(handleBack)
        )
        backButton.accessibilityLabel = *"back"

        let titleLabel = UILabel()
        titleLabel.text = toolDisplayName
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        navigationItem.titleView = titleLabel

        replaceImageButton = UIBarButtonItem(
            image: UIImage(systemName: "photo.on.rectangle"),
            style: .plain,
            target: self,
            action: #selector(onReplaceImage)
        )
        replaceImageButton?.accessibilityLabel = *"replace_image"
        replaceImageButton?.isEnabled = isImageSelected

        overflowMenuButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: buildOverflowMenu()
        )

        navigationItem.leftBarButtonItems = [backButton]
        navigationItem.rightBarButtonItems = [overflowMenuButton!]
    }

    func buildRightBarButtonItems(primaryItems: [UIBarButtonItem]) -> [UIBarButtonItem] {
        if overflowMenuButton == nil {
            overflowMenuButton = UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                menu: buildOverflowMenu()
            )
        }
        refreshOverflowMenu()
        return primaryItems + [overflowMenuButton!]
    }

    private func buildOverflowMenu() -> UIMenu {
        var items: [UIMenuElement] = []

        let replaceAction = UIAction(
            title: *"replace_image",
            image: UIImage(systemName: "photo.on.rectangle"),
            attributes: isImageSelected ? [] : [.disabled]
        ) { [weak self] _ in
            self?.onReplaceImage()
        }
        items.append(replaceAction)

        if compareButton != nil {
            let compareAction = UIAction(
                title: *"compare",
                image: UIImage(systemName: "rectangle.split.2x1"),
                attributes: compareButton?.isEnabled == true ? [] : [.disabled]
            ) { [weak self] _ in
                self?.onCompare()
            }
            items.append(compareAction)
        }

        let saveMenu = UIMenu(
            title: *"save_to_photo_lib",
            image: UIImage(systemName: "square.and.arrow.down"),
            children: createSaveMenu().children
        )
        items.append(saveMenu)

        return UIMenu(title: "", children: items)
    }

    func refreshOverflowMenu() {
        overflowMenuButton?.menu = buildOverflowMenu()
    }

    var toolDisplayName: String {
        switch toolID {
        case "inpainting": return *"tool_inpainting"
        case "background_removal": return *"tool_background_removal"
        case "image_enhance": return *"tool_image_enhance"
        case "mosaic": return *"tool_mosaic"
        case "photo_filter": return *"tool_photo_filter"
        case "text_removal": return *"tool_text_removal"
        case "smart_crop": return *"tool_smart_crop"
        case "depth_image": return *"tool_depth_image"
        case "watermark": return *"tool_watermark"
        default: return toolID
        }
    }

    @objc func handleBack() {
        showUnsavedChangesAlert()
    }

    @objc func onReplaceImage() {
        if hasUnsavedChanges {
            showReplaceImageConfirmation()
        } else {
            replaceImage()
        }
    }

    func showUnsavedChangesAlert() {
        guard hasUnsavedChanges else {
            navigationController?.popViewController(animated: true)
            return
        }

        let alert = UIAlertController(
            title: *"unsaved_changes_title",
            message: *"unsaved_changes_message",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: *"save_and_exit", style: .default) { [weak self] _ in
            self?.saveAndExit()
        })

        alert.addAction(UIAlertAction(title: *"discard_changes", style: .destructive) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })

        alert.addAction(UIAlertAction(title: *"cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }

        present(alert, animated: true)
    }

    private func saveAndExit() {
        saveAsPNG()
        navigationController?.popViewController(animated: true)
    }

    func showReplaceImageConfirmation() {
        let alert = UIAlertController(
            title: *"replace_image",
            message: *"replace_image_unsaved_message",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: *"replace", style: .default) { [weak self] _ in
            self?.replaceImage()
        })
        alert.addAction(UIAlertAction(title: *"cancel", style: .cancel))
        present(alert, animated: true)
    }

    func createSaveMenu() -> UIMenu {
        let savePNGAction = UIAction(title: *"save_png", image: UIImage(systemName: "photo")) { [weak self] _ in
            self?.saveAsPNG()
        }

        let saveJPEGAction = UIAction(title: *"save_jpeg", image: UIImage(systemName: "photo.fill")) { [weak self] _ in
            self?.saveAsJPEG()
        }

        let saveToFilesAction = UIAction(title: *"save_to_files", image: UIImage(systemName: "folder")) { [weak self] _ in
            self?.saveToFiles()
        }

        let copyAction = UIAction(title: *"copy_to_clipboard", image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in
            self?.copyToClipboard()
        }

        let shareAction = UIAction(title: *"share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            self?.share()
        }

        return UIMenu(title: "", children: [savePNGAction, saveJPEGAction, saveToFilesAction, copyAction, shareAction])
    }

    // MARK: - Undo

    func pushUndo(_ image: UIImage) {
        undoStack.append(image)
        undoButton.isEnabled = true
        compareButton?.isEnabled = true
        refreshOverflowMenu()
    }

    @objc func onUndo() {
        guard let img = undoStack.popLast() else { return }
        imageView.image = img
        undoButton.isEnabled = !undoStack.isEmpty
        compareButton?.isEnabled = canUndo
        refreshOverflowMenu()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        if undoStack.count > 3 {
            let lastTwo = undoStack.suffix(2)
            undoStack = [undoStack[0]] + lastTwo
        }
    }

    // MARK: - Save

    /// Returns the image to be saved. Subclasses can override to apply pending changes (e.g. watermark).
    /// The completion block is always called on the main queue.
    func currentImageForSaving(completion: @escaping (UIImage?) -> Void) {
        completion(imageView.image)
    }

    @objc func onSave() {
        saveAsPNG()
    }

    func saveAsPNG() {
        let toolID = self.toolID
        showProcessing(message: *"processing")
        currentImageForSaving { [weak self] image in
            guard let self, let image else { self?.hideProcessing(); return }
            DispatchQueue.global(qos: .userInitiated).async {
                ExportService.saveAsPNG(image) { [weak self] success, error in
                    guard let self else { return }
                    self.hideProcessing()
                    if success {
                        EditHistoryService.shared.addRecord(toolID: toolID, resultImage: image)
                        self.view.makeToast(*"toast_save_success", duration: 2.0, position: .bottom)
                    } else {
                        self.view.makeToast(*"toast_save_error" + " " + (error?.localizedDescription ?? ""), duration: 3.0, position: .bottom)
                    }
                }
            }
        }
    }

    func saveAsJPEG() {
        let toolID = self.toolID
        showProcessing(message: *"processing")
        currentImageForSaving { [weak self] image in
            guard let self, let image else { self?.hideProcessing(); return }
            DispatchQueue.global(qos: .userInitiated).async {
                ExportService.saveAsJPEG(image, quality: 0.9) { [weak self] success, error in
                    guard let self else { return }
                    self.hideProcessing()
                    if success {
                        EditHistoryService.shared.addRecord(toolID: toolID, resultImage: image)
                        self.view.makeToast(*"toast_save_success", duration: 2.0, position: .bottom)
                    } else {
                        self.view.makeToast(*"toast_save_error" + " " + (error?.localizedDescription ?? ""), duration: 3.0, position: .bottom)
                    }
                }
            }
        }
    }

    func saveToFiles() {
        currentImageForSaving { [weak self] image in
            guard let self, let image else { return }
            ExportService.saveToFiles(image, format: .png, from: self)
        }
    }

    func copyToClipboard() {
        showProcessing(message: *"processing")
        currentImageForSaving { [weak self] image in
            guard let self, let image else { self?.hideProcessing(); return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let pngData = image.pngData()
                DispatchQueue.main.async {
                    if let data = pngData {
                        UIPasteboard.general.setData(data, forPasteboardType: "public.png")
                    } else {
                        UIPasteboard.general.image = image
                    }
                    self?.hideProcessing()
                    self?.view.makeToast(*"toast_copy_success", duration: 2.0, position: .bottom)
                }
            }
        }
    }

    func share() {
        currentImageForSaving { [weak self] image in
            guard let self, let image else { return }
            ExportService.presentShareSheet(image: image, from: self)
        }
    }

    // MARK: - Compare

    private var compareView: SplitImageView?

    /// 显示处理前后对比（before 为 originalImage，after 为当前 imageView.image）
    @objc func onCompare() {
        guard imageView.image != nil, canUndo else { return }
        let before = originalImage
        guard let after = imageView.image else { return }

        let splitView = SplitImageView(imageA: before, imageB: after)

        let containerView = UIView(frame: view.bounds)
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        containerView.addSubview(splitView)
        splitView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: containerView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // 关闭按钮放在 splitView 之上
        let closeButton = UIButton(type: .system)
        closeButton.setTitle(*"close", for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeButton.layer.cornerRadius = 16
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        closeButton.addTarget(self, action: #selector(dismissCompare), for: .touchUpInside)
        containerView.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ])

        compareView = splitView
        view.addSubview(containerView)
    }

    @objc private func dismissCompare() {
        compareView?.superview?.removeFromSuperview()
        compareView = nil
    }

    /// 创建对比按钮（子类在 setupNavigationItems 中使用）
    func makeCompareButton() -> UIBarButtonItem {
        let btn = UIBarButtonItem(title: *"compare", style: .plain, target: self, action: #selector(onCompare))
        btn.isEnabled = false
        return btn
    }

    // MARK: - Processing State

    func showProcessing(message: String = "") {
        processingOverlay.state = .processing(message: message)
    }

    func hideProcessing() {
        processingOverlay.state = .idle
    }

    func showError(_ message: String) {
        processingOverlay.state = .error(message)
    }

    func didBeginZoomingImage() {}

    func didEndZoomingImage() {}
}

// MARK: - UIScrollViewDelegate

extension BaseEditingViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        didBeginZoomingImage()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        didEndZoomingImage()
    }
}

// MARK: - EmptyStateViewDelegate

extension BaseEditingViewController: EmptyStateViewDelegate {
    func emptyStateViewDidTapSelectPhoto(_ view: EmptyStateView) {
        presentImagePicker()
    }

    func emptyStateView(_ view: EmptyStateView, didSelectImageSource source: EmptyStateImageSource) {
        presentImagePicker()
    }
}
