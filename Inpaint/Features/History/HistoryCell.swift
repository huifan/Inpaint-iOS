//
//  HistoryCell.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit

final class HistoryCell: UICollectionViewCell {
    static let reuseID = "HistoryCell"

    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.backgroundColor = .secondarySystemBackground
        return iv
    }()

    private let toolLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
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
        contentView.layer.cornerCurve = .continuous

        contentView.addSubview(thumbnailView)
        contentView.addSubview(toolLabel)
        contentView.addSubview(dateLabel)

        thumbnailView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(6)
            make.height.equalTo(thumbnailView.snp.width)
        }

        toolLabel.snp.makeConstraints { make in
            make.top.equalTo(thumbnailView.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview().inset(4)
        }

        dateLabel.snp.makeConstraints { make in
            make.top.equalTo(toolLabel.snp.bottom).offset(2)
            make.leading.trailing.equalToSuperview().inset(4)
            make.bottom.lessThanOrEqualToSuperview().offset(-4)
        }
    }

    func configure(with record: EditRecord, toolName: String) {
        toolLabel.text = toolName

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        dateLabel.text = formatter.string(from: record.date)

        if let thumbnail = EditHistoryService.shared.loadThumbnail(for: record) {
            thumbnailView.image = thumbnail
        } else {
            thumbnailView.image = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
        toolLabel.text = nil
        dateLabel.text = nil
    }
}
