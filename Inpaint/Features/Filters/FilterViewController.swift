//
//  FilterViewController.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit
import Toast_Swift

class FilterViewController: BaseEditingViewController {

    private let processor = FilterProcessor()
    private var selectedFilterID = "original"
    private var intensity: Float = 1.0
    private var isProcessing = false
    private var pendingPreviewUpdate = false
    private var previewWorkItem: DispatchWorkItem?
    private weak var bottomToolbar: UIView?

    // MARK: - Init

    @MainActor override init(toolID: String) {
        super.init(toolID: toolID)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI

    private lazy var filterCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 100)
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .systemBackground
        cv.showsHorizontalScrollIndicator = false
        cv.delegate = self
        cv.dataSource = self
        cv.register(FilterCell.self, forCellWithReuseIdentifier: FilterCell.reuseID)
        return cv
    }()

    private lazy var intensitySlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 1.0
        slider.addTarget(self, action: #selector(intensityChanged(_:)), for: .valueChanged)
        return slider
    }()

    private lazy var intensityLabel: UILabel = {
        let label = UILabel()
        label.text = *"filter_intensity"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    // MARK: - Setup

    override func setupToolUI() {
        if !isImageSelected {
            setupEmptyState(config: EmptyStateConfig(
                toolID: toolID,
                iconName: "camera.filters",
                titleKey: "empty_filter_title",
                descriptionKey: "empty_filter_description",
                buttonTitleKey: "select_photo"
            ))
            return
        }

        setupFilterUI()
    }

    private func setupFilterUI() {
        setupBottomToolbar()
    }

    private func setupBottomToolbar() {
        bottomToolbar?.removeFromSuperview()
        let toolbar = UIView()
        toolbar.backgroundColor = .systemBackground
        bottomToolbar = toolbar
        view.addSubview(toolbar)

        toolbar.addSubview(filterCollectionView)
        toolbar.addSubview(intensityLabel)
        toolbar.addSubview(intensitySlider)

        toolbar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(140)
        }

        filterCollectionView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(100)
        }

        intensityLabel.snp.makeConstraints { make in
            make.top.equalTo(filterCollectionView.snp.bottom).offset(8)
            make.leading.equalToSuperview().offset(16)
        }

        intensitySlider.snp.makeConstraints { make in
            make.top.equalTo(intensityLabel.snp.bottom).offset(4)
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

        let applyButton = UIBarButtonItem(title: *"apply", style: .done, target: self, action: #selector(onApply))
        compareButton = makeCompareButton()
        navigationItem.rightBarButtonItems = buildRightBarButtonItems(primaryItems: [applyButton, undoButton])
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
        setupFilterUI()
        // Apply initial filter (original - no change)
        if let original = originalImage {
            imageView.image = original
        }
        intensitySlider.value = intensity
        filterCollectionView.reloadData()
    }

    override func resetEditState() {
        super.resetEditState()
        selectedFilterID = "original"
        intensity = 1.0
    }

    // MARK: - Actions

    @objc private func intensityChanged(_ sender: UISlider) {
        intensity = sender.value
        scheduleFilterPreview()
    }

    @objc private func onApply() {
        guard let currentImage = imageView.image, let original = originalImage else { return }
        pushUndo(original)
        imageView.image = currentImage
        undoButton.isEnabled = true
        view.makeToast(*"filter_applied", duration: 2.0, position: .bottom)
    }

    private func scheduleFilterPreview(delay: TimeInterval = 0.08) {
        previewWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.applySelectedFilter()
        }
        previewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func applySelectedFilter() {
        guard let original = originalImage else { return }
        guard !isProcessing else {
            pendingPreviewUpdate = true
            return
        }
        isProcessing = true

        let options = ProcessingOptions([
            "filterID": selectedFilterID,
            "intensity": intensity
        ])

        processor.process(
            input: ProcessingInput(image: original),
            options: options
        ) { [weak self] result in
            guard let self = self else { return }
            self.isProcessing = false
            if let output = result.outputImage {
                self.imageView.image = output
            } else if let error = result.error {
                self.view.makeToast(error.localizedDescription, duration: 3.0, position: .bottom)
            }
            if self.pendingPreviewUpdate {
                self.pendingPreviewUpdate = false
                self.scheduleFilterPreview(delay: 0)
            }
        }
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension FilterViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        FilterDefinition.allFilters.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FilterCell.reuseID, for: indexPath) as! FilterCell
        let filter = FilterDefinition.allFilters[indexPath.item]
        if let original = originalImage {
            cell.configure(with: filter, originalImage: original)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let filter = FilterDefinition.allFilters[indexPath.item]
        selectedFilterID = filter.identifier
        intensityLabel.text = filter.nameKey
        scheduleFilterPreview(delay: 0)
    }
}

// MARK: - Filter Cell

final class FilterCell: UICollectionViewCell {
    static let reuseID = "FilterCell"

    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.backgroundColor = .systemGray5
        return iv
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textAlignment = .center
        label.textColor = .label
        return label
    }()

    private let selectionIndicator: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 4
        view.backgroundColor = .systemBlue
        view.isHidden = true
        return view
    }()

    private let context = CIContext()
    private var currentFilterID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(thumbnailView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(selectionIndicator)

        thumbnailView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.width.height.equalTo(60)
        }

        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(thumbnailView.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview()
        }

        selectionIndicator.snp.makeConstraints { make in
            make.top.equalTo(thumbnailView).offset(4)
            make.trailing.equalTo(thumbnailView).offset(-4)
            make.width.height.equalTo(8)
        }
    }

    func configure(with filter: FilterDefinition, originalImage: UIImage) {
        nameLabel.text = *filter.nameKey
        currentFilterID = filter.identifier

        // Generate thumbnail with filter applied
        let thumbnailSize = CGSize(width: 120, height: 120)
        let resizedImage = originalImage.scaleTo(size: thumbnailSize)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let filteredThumbnail = self.applyFilter(to: resizedImage, filter: filter)
            DispatchQueue.main.async {
                guard self.currentFilterID == filter.identifier else { return }
                self.thumbnailView.image = filteredThumbnail ?? resizedImage
            }
        }
    }

    private func applyFilter(to image: UIImage, filter: FilterDefinition) -> UIImage? {
        guard !filter.filters.isEmpty,
              let cgImage = image.cgImage else { return image }

        var ciImage = CIImage(cgImage: cgImage)

        for (filterName, parameters) in filter.filters {
            guard let cifilter = CIFilter(name: filterName) else { continue }
            cifilter.setValue(ciImage, forKey: kCIInputImageKey)
            for (key, value) in parameters {
                cifilter.setValue(value, forKey: key)
            }
            if let output = cifilter.outputImage {
                ciImage = output
            }
        }

        guard let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) else { return image }
        return UIImage(cgImage: outputCGImage)
    }

    override var isSelected: Bool {
        didSet {
            selectionIndicator.isHidden = !isSelected
            thumbnailView.layer.borderWidth = isSelected ? 2 : 0
            thumbnailView.layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : nil
        }
    }
}
