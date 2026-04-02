//
//  SmudgeDrawingView.swift
//  Inpaint
//
//  Created by wudijimao on 2023/12/1.
//

import Foundation
import UIKit

class SmudgeDrawingView: UIView, UIGestureRecognizerDelegate {
    
    private var paths = [UIBezierPath]()
    private var filledPaths = [UIBezierPath]()
    private var path: UIBezierPath = UIBezierPath()
    private var touchPoints: [CGPoint] = []
    var smudgeColor: UIColor = UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 0.5) // 默认为半透明的淡蓝色
    var exportLineColor: UIColor = .white // 涂抹部分导出时的颜色
    var exportBackgroundColor: UIColor = .black // 未涂抹部分导出时的颜色
    var brushSize: CGFloat = 20.0 // 默认笔刷大小
    var onStrokeCompleted: (() -> Void)?


    init() {
        super.init(frame: .zero)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = true
        self.isMultipleTouchEnabled = true
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureAction(_:)))
        panGesture.delegate = self
        panGesture.maximumNumberOfTouches = 1
        self.addGestureRecognizer(panGesture)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // 计算绘制区域的边界
    public var drawBounds: [CGRect] {
        get {
            if paths.isEmpty && filledPaths.isEmpty {
                return []
            }
            var rects = [CGRect]()
            paths.forEach { path in
                guard !path.isEmpty else { return }
                var rect = path.bounds
                // 要扩大path.width的半径
                // 计算扩大的值，这里是路径宽度的一半
                let expandBy = path.lineWidth / 2
                // 扩大 CGRect
                rect = rect.insetBy(dx: -expandBy, dy: -expandBy)
                rect = CGRect(x: rect.origin.x * UIScreen.main.scale, y: rect.origin.y * UIScreen.main.scale, width: rect.size.width * UIScreen.main.scale, height: rect.size.height * UIScreen.main.scale)
                rects.append(rect)
            }
            filledPaths.forEach { path in
                guard !path.isEmpty else { return }
                var rect = path.bounds
                rect = rect.insetBy(dx: -5, dy: -5)
                rect = CGRect(
                    x: rect.origin.x * UIScreen.main.scale,
                    y: rect.origin.y * UIScreen.main.scale,
                    width: rect.size.width * UIScreen.main.scale,
                    height: rect.size.height * UIScreen.main.scale
                )
                rects.append(rect)
            }
            guard rects.count > 0 else {
                return []
            }
            // rects合成一个先，外边处理不了多个，多个为了后边做优化分别inpaint用
            // 初始化一个空的矩形
            var combinedRect = CGRect.null
            // 遍历数组并合并所有矩形
            for rect in rects {
                combinedRect = combinedRect.union(rect)
            }
            // 再往外扩一点避免有生硬的边界
            combinedRect = combinedRect.insetBy(dx: -5, dy: -5)
            return [combinedRect]
        }
    }
    
    @objc func panGestureAction(_ sender: UIPanGestureRecognizer) {
        if sender.numberOfTouches > 1 {
            cancelCurrentStroke()
            return
        }

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

    private func cancelCurrentStroke() {
        touchPoints.removeAll()
        path.removeAllPoints()
        setNeedsDisplay()
    }
    
    @inline(__always)
    func _touchesBegan(touchPoint: CGPoint) {
        path = UIBezierPath()
        path.lineWidth = brushSize
        path.lineCapStyle = .round // 设置线帽为圆形，使曲线封闭部分为圆形
        path.move(to: touchPoint)
        touchPoints.append(touchPoint)
    }
    
    @inline(__always)
    func _touchesMoved(touchPoint: CGPoint) {
        // 计算上一个点和当前点的中间点
        let previousPoint = touchPoints.last ?? touchPoint
        let middlePoint = CGPoint(x: (touchPoint.x + previousPoint.x) / 2.0, y: (touchPoint.y + previousPoint.y) / 2.0)

        // 添加二次贝塞尔曲线，使曲线更平滑
        path.addQuadCurve(to: middlePoint, controlPoint: previousPoint)
        touchPoints.append(touchPoint)

        // 重绘当前触摸点附近的区域
        let redrawRect = CGRect(x: touchPoint.x - brushSize * 2, y: touchPoint.y - brushSize * 2,
                                width: brushSize * 4, height: brushSize * 4)
        setNeedsDisplay(redrawRect)
    }
    
    // 处理触摸结束事件
    @inline(__always)
    func _touchesEnded(touchPoint: CGPoint) {
        // 添加最后一个点到路径中
        if let lastPoint = touchPoints.last {
            let middlePoint = CGPoint(x: (touchPoint.x + lastPoint.x) / 2.0, y: (touchPoint.y + lastPoint.y) / 2.0)
            path.addQuadCurve(to: middlePoint, controlPoint: lastPoint)
        }

        paths.append(path)
        path = UIBezierPath()
        // 清除触摸点，为下一次绘制做准备
        touchPoints.removeAll()

        // 重绘视图以显示最终的绘图
        self.setNeedsDisplay()

        // 通知涂抹完成
        onStrokeCompleted?()
    }

    // 绘制方法
    override func draw(_ rect: CGRect) {
        smudgeColor.setFill()
        filledPaths.forEach { path in
            path.fill()
        }

        smudgeColor.setStroke()
        paths.forEach { path in
            path.stroke()
        }
        path.stroke()
    }

    /// 导出为与目标图像尺寸匹配的灰度蒙版（处理 scaleAspectFit 的偏移）
    /// - Parameter imageSize: 实际图像尺寸，用于计算 aspect-fit 区域
    func exportAsGrayscaleImage(for imageSize: CGSize) -> UIImage? {
        let viewSize = self.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }

        // 计算 aspect-fit 后图像在 view 中的实际显示区域
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        let displayRect: CGRect
        if imageAspect > viewAspect {
            // 图像更宽，上下有留白
            let displayWidth = viewSize.width
            let displayHeight = viewSize.width / imageAspect
            let yOffset = (viewSize.height - displayHeight) / 2.0
            displayRect = CGRect(x: 0, y: yOffset, width: displayWidth, height: displayHeight)
        } else {
            // 图像更高，左右有留白
            let displayHeight = viewSize.height
            let displayWidth = viewSize.height * imageAspect
            let xOffset = (viewSize.width - displayWidth) / 2.0
            displayRect = CGRect(x: xOffset, y: 0, width: displayWidth, height: displayHeight)
        }

        // 输出图像为实际图像尺寸
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        exportBackgroundColor.setFill()
        context.fill(CGRect(origin: .zero, size: imageSize))

        // 将 view 坐标映射到图像坐标
        let scaleX = imageSize.width / displayRect.width
        let scaleY = imageSize.height / displayRect.height

        paths.forEach { p in
            let mappedPath = UIBezierPath(cgPath: p.cgPath)
            // 先平移去掉 aspect-fit 偏移，再缩放到图像坐标
            var transform = CGAffineTransform(translationX: -displayRect.origin.x, y: -displayRect.origin.y)
            transform = transform.concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
            mappedPath.apply(transform)
            exportLineColor.setStroke()
            mappedPath.lineWidth = p.lineWidth * scaleX
            mappedPath.lineCapStyle = .round
            mappedPath.stroke()
        }

        filledPaths.forEach { p in
            let mappedPath = UIBezierPath(cgPath: p.cgPath)
            var transform = CGAffineTransform(translationX: -displayRect.origin.x, y: -displayRect.origin.y)
            transform = transform.concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
            mappedPath.apply(transform)
            exportLineColor.setFill()
            mappedPath.fill()
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    // 导出为灰度图像
    func exportAsGrayscaleImage() -> UIImage? {
        let screenScale = UIScreen.main.scale

        // 放大后的尺寸
        let scaledSize = CGSize(width: self.bounds.size.width * screenScale, height: self.bounds.size.height * screenScale)

        UIGraphicsBeginImageContextWithOptions(scaledSize, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }


        // 绘制背景
        exportBackgroundColor.setFill()
        context.fill(CGRect(x: 0, y: 0, width: scaledSize.width, height: scaledSize.height))

        paths.forEach { path in
            // 调整路径尺寸
            let scaledPath = UIBezierPath(cgPath: path.cgPath)
            scaledPath.apply(CGAffineTransform(scaleX: screenScale, y: screenScale))
            exportLineColor.setStroke()
            scaledPath.lineWidth = brushSize * screenScale // 调整线宽
            scaledPath.lineCapStyle = .round
            scaledPath.stroke()
        }

        filledPaths.forEach { path in
            let scaledPath = UIBezierPath(cgPath: path.cgPath)
            scaledPath.apply(CGAffineTransform(scaleX: screenScale, y: screenScale))
            exportLineColor.setFill()
            scaledPath.fill()
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }


    /// 是否有笔画可以撤销
    var hasStrokes: Bool { !paths.isEmpty || !filledPaths.isEmpty }

    /// 撤销最后一笔涂抹
    @discardableResult
    func undoLastStroke() -> Bool {
        if !paths.isEmpty {
            paths.removeLast()
        } else if !filledPaths.isEmpty {
            filledPaths.removeLast()
        } else {
            return false
        }
        setNeedsDisplay()
        return true
    }

    public func clean() {
        path = UIBezierPath()
        paths = []
        filledPaths = []
        touchPoints = []
        self.setNeedsDisplay()
    }

    /// Draw filled rectangular masks (e.g., from face detection) onto the drawing view.
    /// - Parameter rects: Array of CGRect in the view's coordinate space
    public func drawMasks(_ rects: [CGRect]) {
        for rect in rects {
            let maskPath = UIBezierPath(roundedRect: rect, cornerRadius: brushSize / 2)
            maskPath.lineWidth = brushSize
            paths.append(maskPath)
        }
        self.setNeedsDisplay()
    }

    public func drawFilledMasks(_ rects: [CGRect]) {
        for rect in rects {
            let maskPath = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.22)
            filledPaths.append(maskPath)
        }
        self.setNeedsDisplay()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        return panGesture.numberOfTouches <= 1
    }
}
