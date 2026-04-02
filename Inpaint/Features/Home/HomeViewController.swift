//
//  HomeViewController.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit
import SnapKit
import Toast_Swift
import os.signpost

class HomeViewController: UIViewController {

    // MARK: - Properties

    private let imagePicker = ImagePickerService()
    private var selectedToolID: String?
    private var groupedTools: [(group: ModuleGroup, tools: [ToolDefinition])] = []

    // MARK: - UI

    private lazy var collectionView: UICollectionView = {
        let layout = createLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .systemBackground
        cv.delegate = self
        cv.dataSource = self
        cv.register(ToolCell.self, forCellWithReuseIdentifier: ToolCell.reuseID)
        cv.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: SectionHeaderView.reuseID)
        cv.register(BannerCell.self, forCellWithReuseIdentifier: BannerCell.reuseID)
        cv.register(TipsCell.self, forCellWithReuseIdentifier: TipsCell.reuseID)
        return cv
    }()

    private lazy var headerView: UIView = {
        let container = UIView()

        let bannerCollectionView = UICollectionView(frame: .zero, collectionViewLayout: createBannerLayout())
        bannerCollectionView.backgroundColor = .clear
        bannerCollectionView.isPagingEnabled = true
        bannerCollectionView.showsHorizontalScrollIndicator = false
        bannerCollectionView.delegate = self
        bannerCollectionView.dataSource = self
        bannerCollectionView.register(BannerCell.self, forCellWithReuseIdentifier: BannerCell.reuseID)
        self.bannerCollectionView = bannerCollectionView
        container.addSubview(bannerCollectionView)

        bannerCollectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // Page control
        let pageControl = UIPageControl()
        pageControl.numberOfPages = bannerImages.count
        pageControl.currentPage = 0
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.5)
        pageControl.currentPageIndicatorTintColor = .white
        self.pageControl = pageControl
        container.addSubview(pageControl)

        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(-8)
        }

        return container
    }()

    private var bannerCollectionView: UICollectionView!
    private var pageControl: UIPageControl!

    private lazy var bannerImages: [UIImage] = {
        ["1", "1b", "2", "2b"].compactMap { UIImage(named: $0) }
    }()
    private let tips = [
        ("tips_remove_watermark", "wand.and.stars", "inpainting"),
        ("tips_id_photo", "person.crop.rectangle", "background_removal"),
        ("tips_restore_photo", "sparkles", "enhancement")
    ]

    lazy var settingBtn: UIButton = {
        let btn = UIButton()
        btn.setImage(UIImage(systemName: "gear"), for: .normal)
        btn.addTarget(self, action: #selector(onSetting), for: .touchUpInside)
        return btn
    }()

    private lazy var historyBtn: UIButton = {
        let btn = UIButton()
        btn.setImage(UIImage(systemName: "clock.arrow.circlepath"), for: .normal)
        btn.addTarget(self, action: #selector(onHistory), for: .touchUpInside)
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        let log = OSLog(subsystem: "com.inpaint", category: .pointsOfInterest)
        os_signpost(.begin, log: log, name: "viewDidLoad")
        super.viewDidLoad()

        title = "Magic Photo"
        view.backgroundColor = .systemBackground

        let historyBarBtn = UIBarButtonItem(customView: historyBtn)
        let settingBarBtn = UIBarButtonItem(customView: settingBtn)
        navigationItem.rightBarButtonItems = [settingBarBtn, historyBarBtn]

        os_signpost(.begin, log: log, name: "registerTools")
        registerTools()
        os_signpost(.end, log: log, name: "registerTools")

        os_signpost(.begin, log: log, name: "groupedTools")
        groupedTools = ToolRegistry.shared.groupedTools()
        os_signpost(.end, log: log, name: "groupedTools")

        os_signpost(.begin, log: log, name: "setupUI")
        setupUI()
        os_signpost(.end, log: log, name: "setupUI")

        startBannerTimer()
        os_signpost(.end, log: log, name: "viewDidLoad")
    }

    private var bannerTimer: Timer?

    private func startBannerTimer() {
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.scrollToNextBanner()
        }
    }

    private func scrollToNextBanner() {
        guard bannerCollectionView != nil else { return }
        let currentPage = pageControl?.currentPage ?? 0
        let nextPage = (currentPage + 1) % max(bannerImages.count, 1)
        let indexPath = IndexPath(item: nextPage, section: 0)
        bannerCollectionView?.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        pageControl?.currentPage = nextPage
    }

    @objc private func onHistory() {
        let vc = HistoryViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Tool Registration

    private func registerTools() {
        let registry = ToolRegistry.shared

        // Removal & Repair
        registry.register(InpaintProcessor())
        registry.register(BackgroundRemovalProcessor())
        registry.register(TextRemovalProcessor())

        // Enhancement
        registry.register(EnhancementProcessor())

        // Effects & Creative
        registry.register(MosaicProcessor())
        registry.register(FilterProcessor())
        registry.register(SmartCropProcessor())

        // Composition
        registry.register(DepthImageProcessor())
        registry.register(WatermarkProcessor())
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.addSubview(headerView)
        view.addSubview(collectionView)

        headerView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(12)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(200)
        }

        collectionView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
        }
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / 3.0), heightDimension: .absolute(90))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(90))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 16, trailing: 14)

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(30))
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        section.boundarySupplementaryItems = [header]

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func createBannerLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalWidth(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPaging

        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - Navigation

    @objc private func onSetting() {
        let vc = SettingViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func handleToolSelection(_ tool: ToolDefinition) {
        // Check purchase for pro features
        if tool.tier == .pro {
            Task { @MainActor in
                view.makeToastActivity(.center)
                let purchased = await PurchaseManager.shared.purchases()
                view.hideToastActivity()
                guard purchased else {
                    view.makeToast(*"toast_purchase_failed", duration: 2.0, position: .bottom)
                    return
                }
                self.pickImageForTool(tool.identifier)
            }
        } else {
            pickImageForTool(tool.identifier)
        }
    }

    private func pickImageForTool(_ toolID: String) {
        selectedToolID = toolID
        imagePicker.pickImage(from: self) { [weak self] image in
            guard let self = self, let image = image else { return }
            let scaledImage = image.scaleToLimit(size: CGSize(width: kLimitImageSize, height: kLimitImageSize))
            self.navigateToEditor(toolID: self.selectedToolID ?? toolID, image: scaledImage)
        }
    }

    private func navigateToEditor(toolID: String, image: UIImage) {
        let vc: UIViewController
        switch toolID {
        case "inpainting":
            vc = InpaintViewController(image: image)
        case "background_removal":
            vc = BackgroundRemovalViewController(image: image)
        case "image_enhance":
            vc = EnhancementViewController(image: image)
        case "mosaic":
            vc = MosaicViewController(image: image)
        case "photo_filter":
            vc = FilterViewController(image: image)
        case "text_removal":
            vc = TextRemovalViewController(image: image)
        case "smart_crop":
            vc = SmartCropViewController(image: image)
        case "depth_image":
            vc = DeepImageViewController(image: image)
        case "watermark":
            vc = WatermarkViewController(image: image)
        default:
            return
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if collectionView == bannerCollectionView {
            return 1
        }
        return groupedTools.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == bannerCollectionView {
            return bannerImages.count
        }
        return groupedTools[section].tools.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == bannerCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BannerCell.reuseID, for: indexPath) as! BannerCell
            cell.configure(with: bannerImages[indexPath.item])
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolCell.reuseID, for: indexPath) as! ToolCell
        let tool = groupedTools[indexPath.section].tools[indexPath.item]
        cell.configure(with: tool)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.reuseID, for: indexPath) as! SectionHeaderView
        header.configure(title: groupedTools[indexPath.section].group.displayName)
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == bannerCollectionView {
            return
        }
        let tool = groupedTools[indexPath.section].tools[indexPath.item]
        handleToolSelection(tool)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == bannerCollectionView {
            let page = Int(scrollView.contentOffset.x / scrollView.bounds.width)
            pageControl?.currentPage = page
        }
    }
}

// MARK: - Banner Cell

final class BannerCell: UICollectionViewCell {
    static let reuseID = "BannerCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with image: UIImage?) {
        imageView.image = image
    }
}

// MARK: - Tips Cell

final class TipsCell: UICollectionViewCell {
    static let reuseID = "TipsCell"

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemBlue
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .label
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
        ])
    }

    func configure(titleKey: String, iconName: String) {
        titleLabel.text = *titleKey
        iconView.image = UIImage(systemName: iconName)
    }
}

// MARK: - Section Header

class SectionHeaderView: UICollectionReusableView {
    static let reuseID = "SectionHeaderView"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}
