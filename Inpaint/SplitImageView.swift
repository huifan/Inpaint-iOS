//
//  SplitImageView.swift
//  Inpaint
//
//  Created by wudijimao on 2023/12/3.
//

import Foundation
import UIKit

class SplitImageView: UIView {

    private let imageViewA = UIImageView()
    private let imageViewB = UIImageView()
    private let customMaskView = UIView()
    private let sliderView = UIView()
    private let sliderHandle = UIView()

    // 便利初始化方法接受可选的UIImage
    convenience init(imageA: UIImage?, imageB: UIImage?) {
        self.init(frame: .zero)
        setImageA(imageA)
        setImageB(imageB)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        addPanGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        addPanGesture()
    }

    private func setupViews() {
        // 配置imageViewA和imageViewB
        imageViewA.contentMode = .scaleAspectFit
        imageViewB.contentMode = .scaleAspectFit

        imageViewA.clipsToBounds = true
        imageViewB.clipsToBounds = true

        // 添加视图到SplitImageView
        addSubview(imageViewA)
        addSubview(imageViewB)
        addSubview(sliderView)

        // 设置遮罩
        imageViewB.mask = customMaskView

        // 设置自动布局
        setupConstraints()
        
        // 初始化遮罩视图的frame
        customMaskView.backgroundColor = .white
    }

    private func setupConstraints() {
        imageViewA.translatesAutoresizingMaskIntoConstraints = false
        imageViewB.translatesAutoresizingMaskIntoConstraints = false
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        
        imageViewA.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        imageViewB.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        sliderView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.width.equalTo(2)
            make.centerX.equalToSuperview()
        }

        sliderView.backgroundColor = .white
        sliderView.layer.shadowColor = UIColor.black.cgColor
        sliderView.layer.shadowOpacity = 0.5
        sliderView.layer.shadowRadius = 2
        sliderView.layer.shadowOffset = .zero

        // 中间的拖动手柄
        sliderView.addSubview(sliderHandle)
        sliderHandle.backgroundColor = .white
        sliderHandle.layer.cornerRadius = 16
        sliderHandle.layer.shadowColor = UIColor.black.cgColor
        sliderHandle.layer.shadowOpacity = 0.3
        sliderHandle.layer.shadowRadius = 3
        sliderHandle.layer.shadowOffset = .zero
        sliderHandle.snp.makeConstraints { make in
            make.centerX.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }

        // 手柄上的左右箭头指示
        let arrowLabel = UILabel()
        arrowLabel.text = "◂ ▸"
        arrowLabel.textColor = .darkGray
        arrowLabel.font = .systemFont(ofSize: 11, weight: .bold)
        arrowLabel.textAlignment = .center
        sliderHandle.addSubview(arrowLabel)
        arrowLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    /// 滑块相对于中心的偏移量
    private var sliderOffset: CGFloat = 0
    /// 手势开始时的偏移量
    private var panStartOffset: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        let sliderX = bounds.width / 2.0 + sliderOffset
        customMaskView.frame = CGRect(x: 0, y: 0, width: sliderX, height: bounds.height)
    }

    private func addPanGesture() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.addGestureRecognizer(panGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            panStartOffset = sliderOffset
        case .changed, .ended:
            let translation = gesture.translation(in: self)
            let halfWidth = bounds.width / 2.0
            // 限制在视图边界内
            sliderOffset = min(halfWidth, max(-halfWidth, panStartOffset + translation.x))
            sliderView.snp.updateConstraints { make in
                make.centerX.equalToSuperview().offset(sliderOffset)
            }
            setNeedsLayout()
        default:
            break
        }
    }

    // 允许外部设置图片A，接受UIImage?类型
    public func setImageA(_ image: UIImage?) {
        imageViewA.image = image
    }

    // 允许外部设置图片B，接受UIImage?类型
    public func setImageB(_ image: UIImage?) {
        imageViewB.image = image
    }
}
