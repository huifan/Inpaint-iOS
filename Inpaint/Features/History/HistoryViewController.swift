//
//  HistoryViewController.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit

final class HistoryViewController: UIViewController {

    // MARK: - Properties

    private var records: [EditRecord] = []

    // MARK: - UI

    private lazy var collectionView: UICollectionView = {
        let layout = createLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .systemBackground
        cv.delegate = self
        cv.dataSource = self
        cv.register(HistoryCell.self, forCellWithReuseIdentifier: HistoryCell.reuseID)
        return cv
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = *"history_empty"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = *"history_title"
        view.backgroundColor = .systemBackground

        setupNavigationItems()
        setupUI()
        loadRecords()
    }

    // MARK: - Setup

    private func setupNavigationItems() {
        let clearButton = UIBarButtonItem(
            title: *"clear_all",
            style: .plain,
            target: self,
            action: #selector(onClearAll)
        )
        clearButton.tintColor = .systemRed
        navigationItem.rightBarButtonItem = clearButton
    }

    private func setupUI() {
        view.addSubview(collectionView)
        view.addSubview(emptyLabel)

        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(40)
        }
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / 3.0),
            heightDimension: .absolute(140)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(140)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)

        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - Data

    private func loadRecords() {
        records = EditHistoryService.shared.allRecords()
        emptyLabel.isHidden = !records.isEmpty
        collectionView.reloadData()
    }

    // MARK: - Actions

    @objc private func onClearAll() {
        let alert = UIAlertController(
            title: *"clear_history_confirm_title",
            message: *"clear_history_confirm_message",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: *"cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: *"clear_all", style: .destructive) { [weak self] _ in
            EditHistoryService.shared.clearAll()
            self?.loadRecords()
        })
        present(alert, animated: true)
    }

    private func toolName(for toolID: String) -> String {
        if let processor = ToolRegistry.shared.processor(for: toolID) {
            return processor.toolDefinition.displayName
        }
        return toolID
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension HistoryViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return records.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: HistoryCell.reuseID, for: indexPath) as! HistoryCell
        let record = records[indexPath.item]
        cell.configure(with: record, toolName: toolName(for: record.toolID))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let record = records[indexPath.item]
        guard let resultImage = EditHistoryService.shared.loadResultImage(for: record) else { return }

        let detailVC = HistoryDetailViewController(record: record, resultImage: resultImage, toolName: toolName(for: record.toolID))
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let record = records[indexPath.item]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let deleteAction = UIAction(
                title: *"delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                EditHistoryService.shared.deleteRecord(id: record.id)
                self?.loadRecords()
            }

            return UIMenu(title: "", children: [deleteAction])
        }
    }
}

// MARK: - History Detail ViewController

final class HistoryDetailViewController: UIViewController {

    private let record: EditRecord
    private let resultImage: UIImage
    private let toolName: String

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.delegate = self
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 6.0
        return sv
    }()

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        return iv
    }()

    private lazy var dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    init(record: EditRecord, resultImage: UIImage, toolName: String) {
        self.record = record
        self.resultImage = resultImage
        self.toolName = toolName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = toolName
        view.backgroundColor = .systemBackground

        setupUI()
        setupNavigationItems()

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: record.date)
    }

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        scrollView.addSubview(imageView)
        imageView.image = resultImage
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.height.equalToSuperview()
        }

        view.addSubview(dateLabel)
        dateLabel.snp.makeConstraints { make in
            make.top.equalTo(scrollView.snp.bottom).offset(8)
            make.centerX.equalToSuperview()
        }
    }

    private func setupNavigationItems() {
        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(onShare)
        )
        let deleteButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(onDelete)
        )
        deleteButton.tintColor = .systemRed
        navigationItem.rightBarButtonItems = [shareButton, deleteButton]
    }

    @objc private func onShare() {
        ExportService.presentShareSheet(image: resultImage, from: self)
    }

    @objc private func onDelete() {
        let alert = UIAlertController(
            title: *"delete_history_confirm_title",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: *"cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: *"delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            EditHistoryService.shared.deleteRecord(id: self.record.id)
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}

extension HistoryDetailViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
