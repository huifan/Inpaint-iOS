//
//  SmudgeDrawingView.swift
//  Inpaint
//
//  Created by wudijimao on 2023/12/1.
//

import Foundation
import UIKit

class SmudgeDrawingView: UIView {
    
    private var paths = [UIBezierPath]()
    private var path: UIBezierPath = UIBezierPath()
    private var touchPoints: [CGPoint] = []
    var smudgeColor: UIColor = UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 0.5) // 半透明的淡蓝色
    var exportLineColor: UIColor = .white // 涂抹部分导出时的颜色
    var exportBackgroundColor: UIColor = .black // 未涂抹部分导出时的颜色
    var brushSize: CGFloat = 20.0 // 默认笔刷大小

    /// ISNet mask: grayscale UIImage.
    /// After resizeAndInvertMaskForDisplay: white=background(remove), black=subject(keep).
    /// Display: clip(to: mask) + blue fill → blue only on background areas.
    var isnetMaskOverlay: UIImage? {
        didSet {
            setNeedsDisplay()
        }
    }

    init() {
        super.init(frame: .zero)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = true
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureAction(_:)))
        panGesture.maximumNumberOfTouches = 1
        self.addGestureRecognizer(panGesture)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // 计算绘制区域的边界
    public var drawBounds: [CGRect] {
        get {
            if paths.isEmpty {
                return []
            }
            var rects = [CGRect]()
            paths.forEach { path in
                guard !path.isEmpty else { return }
                var rect = path.bounds
                let expandBy = path.lineWidth / 2
                rect = rect.insetBy(dx: -expandBy, dy: -expandBy)
                rect = CGRect(x: rect.origin.x * UIScreen.main.scale,
                               y: rect.origin.y * UIScreen.main.scale,
                               width: rect.size.width * UIScreen.main.scale,
                               height: rect.size.height * UIScreen.main.scale)
                rects.append(rect)
            }
            guard rects.count > 0 else {
                return []
            }
            var combinedRect = CGRect.null
            for rect in rects {
                combinedRect = combinedRect.union(rect)
            }
            combinedRect = combinedRect.insetBy(dx: -5, dy: -5)
            return [combinedRect]
        }
    }
    
    @objc func panGestureAction(_ sender: UIPanGestureRecognizer) {
        let touchPoint = sender.location(in: self)
        
        switch sender.state {
        case .began:
            _touchesBegan(touchPoint: touchPoint)
        case .changed:
            _touchesMoved(touchPoint: touchPoint)
        case .ended:
            _touchesEnded(touchPoint: touchPoint)
        case .cancelled:
            touchPoints.removeAll()
            path.removeAllPoints()
            self.setNeedsDisplay()
        default:
            break
        }
    }
    
    @inline(__always)
    func _touchesBegan(touchPoint: CGPoint) {
        path = UIBezierPath()
        path.lineWidth = brushSize
        path.lineCapStyle = .round
        path.move(to: touchPoint)
        touchPoints.append(touchPoint)
    }
    
    @inline(__always)
    func _touchesMoved(touchPoint: CGPoint) {
        let previousPoint = touchPoints.last ?? touchPoint
        let middlePoint = CGPoint(x: (touchPoint.x + previousPoint.x) / 2.0, y: (touchPoint.y + previousPoint.y) / 2.0)
        path.addQuadCurve(to: middlePoint, controlPoint: previousPoint)
        touchPoints.append(touchPoint)
        let redrawRect = CGRect(x: touchPoint.x - brushSize * 2, y: touchPoint.y - brushSize * 2,
                                width: brushSize * 4, height: brushSize * 4)
        setNeedsDisplay(redrawRect)
    }
    
    @inline(__always)
    func _touchesEnded(touchPoint: CGPoint) {
        if let lastPoint = touchPoints.last {
            let middlePoint = CGPoint(x: (touchPoint.x + lastPoint.x) / 2.0, y: (touchPoint.y + lastPoint.y) / 2.0)
            path.addQuadCurve(to: middlePoint, controlPoint: lastPoint)
        }
        paths.append(path)
        path = UIBezierPath()
        touchPoints.removeAll()
        self.setNeedsDisplay()
    }

    // 绘制方法
    override func draw(_ rect: CGRect) {
        // Draw user brush strokes
        smudgeColor.setStroke()
        paths.forEach { p in
            p.stroke()
        }
        path.stroke()

        // Draw ISNet mask preview:
        // isnetMaskOverlay: white=background(remove), black=subject(keep)
        // clip(to: mask): white pixels → transparent → blue fill shows through
        //                 black pixels → opaque → blue fill blocked
        // Result: blue only on background areas (what will be removed)
        if let maskImg = isnetMaskOverlay, let cg = maskImg.cgImage {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.saveGState()
            context.clip(to: rect, mask: cg)
            UIColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.35).setFill()
            context.fill(rect)
            context.restoreGState()
        }
    }

    // 导出为灰度图像（用于 inpainting）
    // 策略：isnetMaskOverlay 已经经过 resizeAndInvertMaskForDisplay 处理，
    // 取反后的 mask: white=background(消除), black=subject(保留)
    // 导出时: 白色=消除区域, 黑色=保留区域
    // 直接把 inverted mask 绘制到画布上，不做额外裁剪
    func exportAsGrayscaleImage() -> UIImage? {
        let screenScale = UIScreen.main.scale
        let w = Int(self.bounds.size.width * screenScale)
        let h = Int(self.bounds.size.height * screenScale)

        UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Step 1: Fill entire canvas with WHITE (all = to be inpainted / removed)
        // inpaint 期望白色=消除区域
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h)

        // Step 2: Draw user strokes as BLACK (subject = to be preserved / not removed)
        exportLineColor.setFill()
        paths.forEach { p in
            let scaledPath = UIBezierPath(cgPath: p.cgPath)
            scaledPath.apply(CGAffineTransform(scaleX: screenScale, y: screenScale))
            scaledPath.lineWidth = brushSize * screenScale
            scaledPath.lineCapStyle = .round
            scaledPath.stroke()
        }

        // Step 3: Apply ISNet inverted mask
        // isnetMaskOverlay is already: white=background(remove), black=subject(keep)
        // Draw it to cover the background (white in mask = background to remove)
        if let maskImg = isnetMaskOverlay {
            // Draw the inverted mask directly (white=background=remove)
            maskImg.draw(in: CGRect(x: 0, y: 0, width: w, height: h)
        }

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }

    public func clean() {
        path = UIBezierPath()
        paths = []
        touchPoints = []
        isnetMaskOverlay = nil
        self.setNeedsDisplay()
    }
}

// MARK: - UIImage Extension for ISNet Mask Inversion

extension UIImage {
    /// Invert a grayscale mask: white→black, black→white.
    /// Used to convert ISNet output (white=subject) to inpaint format (white=remove).
    func invertedGrayscale() -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width

        var pixelData = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height)

        // Invert: 255 - value
        for i in 0..<pixelData.count {
            pixelData[i] = 255 - pixelData[i]
        }

        guard let outContext = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        guard let outCGImage = outContext.makeImage() else { return nil }
        return UIImage(cgImage: outCGImage)
    }
}
