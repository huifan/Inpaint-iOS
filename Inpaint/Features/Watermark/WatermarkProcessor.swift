//
//  WatermarkProcessor.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit

final class WatermarkProcessor: ImageProcessor {
    let identifier = "watermark"

    let toolDefinition = ToolDefinition(
        identifier: "watermark",
        nameKey: "tool_watermark",
        iconName: "text.badge.plus",
        tier: .free,
        moduleGroup: .composition
    )

    var isReady: Bool { true }

    func preload() {}
    func unload() {}

    func process(input: ProcessingInput, options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        guard let config = options.watermarkConfig else {
            completion(.failure(NSError(domain: "WatermarkProcessor", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Missing watermark config"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let renderer = UIGraphicsImageRenderer(size: input.image.size)
            let result = renderer.image { context in
                input.image.draw(at: .zero)
                if config.isTiled {
                    self.drawTiled(config: config, in: context.cgContext, imageSize: input.image.size)
                } else {
                    self.drawSingle(config: config, in: context.cgContext, imageSize: input.image.size)
                }
            }
            DispatchQueue.main.async {
                completion(.success(result))
            }
        }
    }

    private func drawSingle(config: WatermarkConfig, in context: CGContext, imageSize: CGSize) {
        context.saveGState()
        context.setAlpha(config.opacity)

        let position = CGPoint(
            x: config.position.x * imageSize.width,
            y: config.position.y * imageSize.height
        )
        context.translateBy(x: position.x, y: position.y)
        context.rotate(by: config.rotation)
        context.scaleBy(x: config.scale, y: config.scale)
        drawContent(config: config, in: context, referenceSize: imageSize)

        context.restoreGState()
    }

    private func drawTiled(config: WatermarkConfig, in context: CGContext, imageSize: CGSize) {
        let spacing: CGFloat = min(imageSize.width, imageSize.height) * 0.35
        let angle: CGFloat = -.pi / 4
        let diagonal = sqrt(imageSize.width * imageSize.width + imageSize.height * imageSize.height)
        let count = Int(diagonal / spacing) + 2

        context.saveGState()
        context.setAlpha(config.opacity)

        for i in -count...count {
            for j in -count...count {
                context.saveGState()
                let x = imageSize.width / 2 + CGFloat(i) * spacing
                let y = imageSize.height / 2 + CGFloat(j) * spacing
                context.translateBy(x: x, y: y)
                context.rotate(by: angle)
                context.scaleBy(x: config.scale * 0.5, y: config.scale * 0.5)
                drawContent(config: config, in: context, referenceSize: imageSize)
                context.restoreGState()
            }
        }

        context.restoreGState()
    }

    private func drawContent(config: WatermarkConfig, in context: CGContext, referenceSize: CGSize) {
        switch config.type {
        case .text(let text, let font, let color):
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attrs)

        case .image(let img):
            guard img.size.width > 0 else { return }
            let baseWidth = referenceSize.width * 0.3
            let aspectRatio = img.size.height / img.size.width
            let drawSize = CGSize(width: baseWidth, height: baseWidth * aspectRatio)
            img.draw(in: CGRect(x: -drawSize.width / 2, y: -drawSize.height / 2,
                                width: drawSize.width, height: drawSize.height))
        }
    }
}
