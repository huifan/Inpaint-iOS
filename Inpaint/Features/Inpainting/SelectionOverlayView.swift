//
//  SelectionOverlayView.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit

/// Overlay view that displays highlighted regions for selected objects.
final class SelectionOverlayView: UIView {

    /// Represents a selected object region
    struct SelectionRegion {
        let path: UIBezierPath
        let color: UIColor
    }

    /// Array of selected regions
    private(set) var selections: [SelectionRegion] = []

    /// Color for selected regions (default: blue with 30% alpha)
    var selectionColor: UIColor = UIColor.systemBlue.withAlphaComponent(0.3) {
        didSet { setNeedsDisplay() }
    }

    /// Border color for selected regions
    var borderColor: UIColor = UIColor.systemBlue {
        didSet { setNeedsDisplay() }
    }

    /// Border width for selected regions
    var borderWidth: CGFloat = 2.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    /// Add a selection region from a mask image.
    /// - Parameter maskImage: Binary mask (white = selected)
    func addSelection(from maskImage: UIImage) {
        guard let cgImage = maskImage.cgImage else { return }

        // Find bounding rect of white pixels
        let width = cgImage.width
        let height = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return }

        var minX = width, minY = height, maxX = 0, maxY = 0

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let stride = cgImage.bytesPerRow

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * stride + x * bytesPerPixel
                let alpha = bytesPerPixel >= 4 ? bytes[idx + 3] : bytes[idx]
                if alpha > 128 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX < maxX && minY < maxY else { return }

        // Convert to view coordinates (accounting for scale)
        let scale = UIScreen.main.scale
        let viewRect = CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX) / scale,
            height: CGFloat(maxY - minY) / scale
        )

        let path = UIBezierPath(roundedRect: viewRect, cornerRadius: 8)
        let region = SelectionRegion(path: path, color: selectionColor)
        selections.append(region)
        setNeedsDisplay()
    }

    /// Add a selection region from a rectangle.
    /// - Parameter rect: Selection rectangle in view coordinates
    func addSelection(rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        let region = SelectionRegion(path: path, color: selectionColor)
        selections.append(region)
        setNeedsDisplay()
    }

    /// Add a selection region from multiple rectangles (e.g., face detection).
    /// - Parameter rects: Array of rectangles in view coordinates
    func addSelections(rects: [CGRect]) {
        for rect in rects {
            addSelection(rect: rect)
        }
    }

    /// Remove the last added selection.
    func removeLastSelection() {
        guard !selections.isEmpty else { return }
        selections.removeLast()
        setNeedsDisplay()
    }

    /// Clear all selections.
    func clearSelections() {
        selections.removeAll()
        setNeedsDisplay()
    }

    /// Get all selection rectangles in view coordinates.
    var selectionRects: [CGRect] {
        selections.map { $0.path.bounds }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for region in selections {
            // Draw fill
            context.saveGState()
            region.color.setFill()
            region.path.fill()
            context.restoreGState()

            // Draw border
            borderColor.setStroke()
            region.path.lineWidth = borderWidth
            region.path.stroke()
        }
    }
}

// MARK: - Animated Selection Feedback

extension SelectionOverlayView {

    /// Flash animation when a new selection is made.
    func flashSelection(at rect: CGRect) {
        // Create temporary highlight layer
        let highlightView = UIView(frame: rect)
        highlightView.backgroundColor = selectionColor
        highlightView.layer.cornerRadius = 8
        highlightView.alpha = 0
        addSubview(highlightView)

        UIView.animate(withDuration: 0.15, animations: {
            highlightView.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.1, options: [], animations: {
                highlightView.alpha = 0
            }) { _ in
                highlightView.removeFromSuperview()
            }
        }
    }
}
