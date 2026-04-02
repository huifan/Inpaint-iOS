//
//  WarmupViewController.swift
//  Inpaint
//

import UIKit

/// 首次启动时显示，等待 CoreML 模型完成设备特化后跳转主页。
final class WarmupViewController: UIViewController {

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconView = UIImageView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startWarmup()
    }

    private func setupUI() {
        iconView.image = UIImage(named: "LaunchIcon")
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 22
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Magic Photo"
        titleLabel.font = .systemFont(ofSize: 24, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "正在准备 AI 模型…"
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        view.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(spinner)
        view.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            iconView.widthAnchor.constraint(equalToConstant: 100),
            iconView.heightAnchor.constraint(equalToConstant: 100),

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 32),

            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
        ])
    }

    private func startWarmup() {
        LaMaImageInpenting.shared.warmup { [weak self] in
            self?.transitionToHome()
        }
    }

    private func transitionToHome() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")

        let homeVC = HomeViewController()
        let nav = UINavigationController(rootViewController: homeVC)
        nav.modalTransitionStyle = .crossDissolve
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
