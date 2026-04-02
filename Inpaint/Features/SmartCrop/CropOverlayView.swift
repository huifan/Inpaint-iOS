//
//  CropOverlayView.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import SnapKit

protocol CropOverlayViewDelegate: AnyObject {
    func cropOverlayView(_ view: CropOverlayView, didUpdateCropRect cropRect: CGRect)
}

final class CropOverlayView: UIView {

    weak var delegate: CropOverlayViewDelegate?

    /// Crop rect in view coordinates
    var cropRect: CGRect {
        didSet {
            setNeedsDisplay()
            updateHandlePositions()
        }
    }

    /// Optional aspect ratio constraint (nil = free crop)
    var aspectRatio: CGFloat?

    /// Whether the crop is active (user is dragging)
    private(set) var isActive = false

    // MARK: - Handle Properties

    private let handleSize: CGFloat = 44
    private let handleVisualSize: CGFloat = 12
    private let gridLineWidth: CGFloat = 1.0

    // MARK: - UI Components

    private let maskLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    private lazy var topLeftHandle = createHandle()
    private lazy var topRightHandle = createHandle()
    private lazy var bottomLeftHandle = createHandle()
    private lazy var bottomRightHandle = createHandle()

    private var activeHandle: UIView?
    private var initialCropRect: CGRect = .zero
    private var initialTouchPoint: CGPoint = .zero

    // MARK: - Init

    init(cropRect: CGRect) {
        self.cropRect = cropRect
        super.init(frame: .zero)
        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .clear
        isUserInteractionEnabled = true

        // Mask layer (semi-transparent outside crop area)
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        maskLayer.fillRule = .evenOdd
        layer.addSublayer(maskLayer)

        // Grid layer (rule of thirds)
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        gridLayer.fillColor = nil
        gridLayer.lineWidth = gridLineWidth
        layer.addSublayer(gridLayer)

        // Border layer
        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 2
        layer.addSublayer(borderLayer)

        // Add handles
        [topLeftHandle, topRightHandle, bottomLeftHandle, bottomRightHandle].forEach {
            addSubview($0)
        }

        updateHandlePositions()
    }

    private func createHandle() -> UIView {
        let handle = UIView()
        handle.backgroundColor = .white
        handle.layer.cornerRadius = handleVisualSize / 2
        handle.layer.shadowColor = UIColor.black.cgColor
        handle.layer.shadowOffset = CGSize(width: 0, height: 2)
        handle.layer.shadowOpacity = 0.3
        handle.layer.shadowRadius = 2
        return handle
    }

    private func setupGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayers()
        updateHandlePositions()
    }

    private func updateLayers() {
        // Update mask path
        let outerPath = UIBezierPath(rect: bounds)
        let innerPath = UIBezierPath(rect: cropRect)
        outerPath.append(innerPath)
        maskLayer.path = outerPath.cgPath

        // Update grid path
        let gridPath = UIBezierPath()

        // Vertical lines (rule of thirds)
        let thirdWidth = cropRect.width / 3
        gridPath.move(to: CGPoint(x: cropRect.minX + thirdWidth, y: cropRect.minY))
        gridPath.addLine(to: CGPoint(x: cropRect.minX + thirdWidth, y: cropRect.maxY))
        gridPath.move(to: CGPoint(x: cropRect.minX + 2 * thirdWidth, y: cropRect.minY))
        gridPath.addLine(to: CGPoint(x: cropRect.minX + 2 * thirdWidth, y: cropRect.maxY))

        // Horizontal lines (rule of thirds)
        let thirdHeight = cropRect.height / 3
        gridPath.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + thirdHeight))
        gridPath.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + thirdHeight))
        gridPath.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + 2 * thirdHeight))
        gridPath.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + 2 * thirdHeight))

        gridLayer.path = gridPath.cgPath

        // Update border path
        borderLayer.path = UIBezierPath(rect: cropRect).cgPath
    }

    private func updateHandlePositions() {
        let halfSize = handleVisualSize / 2

        topLeftHandle.center = CGPoint(x: cropRect.minX, y: cropRect.minY)
        topRightHandle.center = CGPoint(x: cropRect.maxX, y: cropRect.minY)
        bottomLeftHandle.center = CGPoint(x: cropRect.minX, y: cropRect.maxY)
        bottomRightHandle.center = CGPoint(x: cropRect.maxX, y: cropRect.maxY)
    }

    // MARK: - Gesture Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            isActive = true
            activeHandle = handleAt(location)
            initialCropRect = cropRect
            initialTouchPoint = location

        case .changed:
            guard let handle = activeHandle else { return }
            let translation = gesture.translation(in: self)

            var newRect = initialCropRect

            switch handle {
            case topLeftHandle:
                newRect.origin.x += translation.x
                newRect.origin.y += translation.y
                newRect.size.width -= translation.x
                newRect.size.height -= translation.y
            case topRightHandle:
                newRect.origin.y += translation.y
                newRect.size.width += translation.x
                newRect.size.height -= translation.y
            case bottomLeftHandle:
                newRect.origin.x += translation.x
                newRect.size.width -= translation.x
                newRect.size.height += translation.y
            case bottomRightHandle:
                newRect.size.width += translation.x
                newRect.size.height += translation.y
            default:
                break
            }

            // Apply aspect ratio constraint if set
            if let ratio = aspectRatio {
                newRect = applyAspectRatio(ratio, to: newRect, from: initialCropRect)
            }

            // Ensure minimum size
            let minSize: CGFloat = 50
            if newRect.width >= minSize && newRect.height >= minSize {
                // Ensure crop rect stays within bounds
                newRect = constrainToBounds(newRect)
                cropRect = newRect
                delegate?.cropOverlayView(self, didUpdateCropRect: cropRect)
            }

        case .ended, .cancelled:
            isActive = false
            activeHandle = nil

        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Could be used to reset or confirm crop
    }

    private func handleAt(_ point: CGPoint) -> UIView? {
        let touchArea = handleSize
        let handles = [topLeftHandle, topRightHandle, bottomLeftHandle, bottomRightHandle]

        for handle in handles {
            let handleRect = handle.frame.insetBy(dx: -touchArea/2, dy: -touchArea/2)
            if handleRect.contains(point) {
                return handle
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func applyAspectRatio(_ ratio: CGFloat, to newRect: CGRect, from originalRect: CGRect) -> CGRect {
        var result = newRect

        // Determine which dimension to adjust based on drag direction
        let dx = abs(newRect.width - originalRect.width)
        let dy = abs(newRect.height - originalRect.height)

        if dx > dy {
            // Horizontal drag - adjust height to match ratio
            result.size.height = newRect.width / ratio
        } else {
            // Vertical drag - adjust width to match ratio
            result.size.width = newRect.height * ratio
        }

        // Keep the same center as much as possible
        let centerX = originalRect.midX
        let centerY = originalRect.midY
        result.origin.x = centerX - result.width / 2
        result.origin.y = centerY - result.height / 2

        return result
    }

    private func constrainToBounds(_ rect: CGRect) -> CGRect {
        var result = rect

        if result.origin.x < bounds.minX {
            result.origin.x = bounds.minX
        }
        if result.origin.y < bounds.minY {
            result.origin.y = bounds.minY
        }
        if result.maxX > bounds.maxX {
            result.origin.x = bounds.maxX - result.width
        }
        if result.maxY > bounds.maxY {
            result.origin.y = bounds.maxY - result.height
        }

        return result
    }

    // MARK: - Public Methods

    func setCropRect(_ rect: CGRect, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.3) {
                self.cropRect = rect
                self.layoutIfNeeded()
            }
        } else {
            cropRect = rect
        }
    }

    /// Convert crop rect from view coordinates to image coordinates
    func cropRectInImageCoordinates(imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let aspectFitScale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * aspectFitScale) / 2
        let offsetY = (viewSize.height - imageSize.height * aspectFitScale) / 2

        // Convert from view coordinates to image coordinates
        let imageRect = CGRect(
            x: (cropRect.origin.x - offsetX) / aspectFitScale,
            y: (cropRect.origin.y - offsetY) / aspectFitScale,
            width: cropRect.width / aspectFitScale,
            height: cropRect.height / aspectFitScale
        )

        // Ensure rect is within image bounds
        return imageRect.intersection(CGRect(origin: .zero, size: imageSize))
    }
}
