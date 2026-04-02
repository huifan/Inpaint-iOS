//
//  ToolCell.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit

class ToolCell: UICollectionViewCell {

    static let reuseID = "ToolCell"

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemBlue
        return iv
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private let proTag: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.textAlignment = .center
        label.text = "PRO"
        label.textColor = .white
        label.backgroundColor = .systemOrange
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isHidden = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous

        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(proTag)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        proTag.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -10),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),

            proTag.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            proTag.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            proTag.widthAnchor.constraint(equalToConstant: 28),
            proTag.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    func configure(with tool: ToolDefinition) {
        nameLabel.text = tool.displayName

        // Try SF Symbol first, fallback to named asset
        if let sfImage = UIImage(systemName: tool.iconName) {
            iconView.image = sfImage
        } else {
            iconView.image = UIImage(named: tool.iconName)
        }

        proTag.isHidden = (tool.tier == .free)
    }

    override var isSelected: Bool {
        didSet {
            if isSelected {
                contentView.layer.shadowColor = UIColor.black.cgColor
                contentView.layer.shadowOffset = CGSize(width: 0, height: 2)
                contentView.layer.shadowOpacity = 0.2
                contentView.layer.shadowRadius = 4

                UIView.animate(withDuration: 0.2) {
                    self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
                }
            } else {
                contentView.layer.shadowOpacity = 0

                UIView.animate(withDuration: 0.2) {
                    self.transform = .identity
                }
            }
        }
    }
}

