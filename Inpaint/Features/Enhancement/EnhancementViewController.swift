//
//  EnhancementViewController.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit
import Toast_Swift

class EnhancementViewController: BaseEditingViewController {

    private let processor = EnhancementProcessor()
    private var enhancementMode: EnhancementMode = .autoEnhance

    // MARK: - Init

    @MainActor override init(toolID: String) {
        super.init(toolID: toolID)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI

    private lazy var modeSelector: UISegmentedControl = {
        let items = [
            *"enhance_auto",
            *"enhance_sr_2x",
            *"enhance_sr_4x",
            *"enhance_denoise"
        ]
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        return sc
    }()

    private let progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.isHidden = true
        return pv
    }()

    // MARK: - Setup

    override func setupToolUI() {
        if !isImageSelected {
            setupEmptyState(config: EmptyStateConfig(
                toolID: toolID,
                iconName: "sparkles",
                titleKey: "empty_enhance_title",
                descriptionKey: "empty_enhance_description",
                buttonTitleKey: "select_photo"
            ))
            return
        }

        setupEnhancementUI()
    }

    private func setupEnhancementUI() {
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

        view.addSubview(progressBar)
        progressBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalTo(toolbar.snp.top).offset(-8)
        }

        scrollView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(toolbar.snp.top)
        }
    }

    override func setupNavigationItems() {
        setupUnifiedNavigationItems()

        let enhanceButton = UIBarButtonItem(
            title: *"enhance",
            style: .done, target: self,
            action: #selector(onEnhance)
        )
        compareButton = makeCompareButton()
        navigationItem.rightBarButtonItems = buildRightBarButtonItems(primaryItems: [enhanceButton, undoButton])
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
        setupEnhancementUI()
    }

    override func resetEditState() {
        super.resetEditState()
        enhancementMode = .autoEnhance
        modeSelector.selectedSegmentIndex = 0
        progressBar.isHidden = true
    }

    // MARK: - Actions

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: enhancementMode = .autoEnhance
        case 1: enhancementMode = .superResolution2x
        case 2: enhancementMode = .superResolution4x
        case 3: enhancementMode = .denoise
        default: break
        }
    }

    @objc private func onEnhance() {
        guard let inputImage = imageView.image else { return }

        let isSR = (enhancementMode == .superResolution2x ||
                    enhancementMode == .superResolution4x)

        if isSR {
            // Show progress bar for SR processing
            progressBar.isHidden = false
            progressBar.progress = 0
            showProcessing(message: *"processing_sr")
        } else {
            showProcessing(message: *"processing")
        }

        let options = ProcessingOptions(["enhancementMode": enhancementMode])

        // Use progress-aware processing for SR
        processor.processWithProgress(
            input: ProcessingInput(image: inputImage),
            options: options,
            progress: isSR ? { [weak self] progress in
                DispatchQueue.main.async {
                    self?.progressBar.progress = progress
                }
            } : nil
        ) { [weak self] result in
            guard let self else { return }
            self.hideProcessing()
            self.progressBar.isHidden = true
            if let output = result.outputImage {
                self.pushUndo(inputImage)
                self.imageView.image = output
            } else if let error = result.error {
                self.view.makeToast(error.localizedDescription, duration: 3.0, position: .bottom)
            }
        }
    }
}
