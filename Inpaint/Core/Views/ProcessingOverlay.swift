//
//  ProcessingOverlay.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit

class ProcessingOverlay: UIView {

    enum State {
        case idle
        case processing(message: String)
        case progress(message: String, value: Float)
        case complete
        case error(String)
    }

    var state: State = .idle {
        didSet { updateUI() }
    }

    private let blurView: UIVisualEffectView = {
        let effect = UIBlurEffect(style: .systemUltraThinMaterial)
        return UIVisualEffectView(effect: effect)
    }()

    private let spinner = UIActivityIndicatorView(style: .large)

    private let progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.isHidden = true
        return pv
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
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
        isHidden = true

        addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let stack = UIStackView(arrangedSubviews: [spinner, messageLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 60),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -60),
            progressView.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 16)
        ])
    }

    private func updateUI() {
        switch state {
        case .idle, .complete:
            isHidden = true
            spinner.stopAnimating()
            progressView.isHidden = true
        case .processing(let message):
            isHidden = false
            spinner.startAnimating()
            progressView.isHidden = true
            messageLabel.text = message
        case .progress(let message, let value):
            isHidden = false
            spinner.startAnimating()
            progressView.isHidden = false
            progressView.progress = value
            messageLabel.text = message
        case .error(let message):
            isHidden = false
            spinner.stopAnimating()
            progressView.isHidden = true
            messageLabel.text = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.state = .idle
            }
        }
    }
}
