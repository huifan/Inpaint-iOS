//
//  BaseEditingViewController.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit
import SnapKit
import Toast_Swift

class BaseEditingViewController: UIViewController {

    // MARK: - Properties

    let originalImage: UIImage

    /// Override in subclasses to record edit history
    var toolID: String { "unknown" }

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

    lazy var undoButton = UIBarButtonItem(title: *"undo", style: .plain, target: self, action: #selector(onUndo))

    // MARK: - Init

    init(image: UIImage) {
        self.originalImage = image
        super.init(nibName: nil, bundle: nil)
        imageView.image = image
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        setupBaseUI()
        setupToolUI()
        setupNavigationItems()
    }

    // MARK: - Base UI Setup

    private func setupBaseUI() {
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }

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
        undoButton.isEnabled = false
        let saveMenu = createSaveMenu()
        let saveButton = UIBarButtonItem(title: *"save_to_photo_lib", menu: saveMenu)
        navigationItem.rightBarButtonItems = [saveButton, undoButton]
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
        // 有操作历史后启用对比按钮
        compareButton?.isEnabled = true
    }

    /// 子类设置此属性以自动管理对比按钮状态
    var compareButton: UIBarButtonItem?

    @objc func onUndo() {
        guard let img = undoStack.popLast() else { return }
        imageView.image = img
        undoButton.isEnabled = !undoStack.isEmpty
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
                        self.view.makeToast("\(*"toast_save_error") \(error?.localizedDescription ?? "")", duration: 3.0, position: .bottom)
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
                        self.view.makeToast("\(*"toast_save_error") \(error?.localizedDescription ?? "")", duration: 3.0, position: .bottom)
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
}

// MARK: - UIScrollViewDelegate

extension BaseEditingViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }
}
