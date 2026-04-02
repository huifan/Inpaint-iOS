//
//  BackgroundRemovalProcessor.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import Vision
import CoreImage

final class BackgroundRemovalProcessor: ImageProcessor {

    let identifier = "background_removal"

    let toolDefinition = ToolDefinition(
        identifier: "background_removal",
        nameKey: "tool_background_removal",
        iconName: "person.crop.rectangle",
        tier: .free,
        moduleGroup: .removalRepair
    )

    private let ciContext = CIContext()

    var isReady: Bool { true }

    func preload() {}

    func unload() {}

    func process(
        input: ProcessingInput,
        options: ProcessingOptions,
        completion: @escaping (ProcessingResult) -> Void
    ) {
        let mode: BackgroundMode = options.value(for: "backgroundMode") ?? .transparent

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = removeBackground(from: input.image, mode: mode)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func removeBackground(from image: UIImage, mode: BackgroundMode) -> ProcessingResult {
        guard let cgImage = image.cgImage else {
            return .failure(BackgroundRemovalError.invalidImage)
        }

        // Step 1: Generate foreground mask
        guard #available(iOS 17.0, *) else {
            return .failure(BackgroundRemovalError.notSupported)
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
        } catch {
            return .failure(error)
        }

        guard let observation = request.results?.first else {
            return .failure(BackgroundRemovalError.noMaskGenerated)
        }

        do {
            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )

            let originalCI = CIImage(cgImage: cgImage)
            let maskCI = CIImage(cvPixelBuffer: maskBuffer)

            let resultImage: UIImage?

            switch mode {
            case .transparent:
                resultImage = applyTransparentBackground(original: originalCI, mask: maskCI)
            case .solidColor(let color):
                resultImage = applySolidBackground(original: originalCI, mask: maskCI, color: color)
            case .blurred(let radius):
                resultImage = applyBlurredBackground(original: originalCI, mask: maskCI, radius: radius)
            case .customImage(let bgImage):
                resultImage = applyCustomBackground(original: originalCI, mask: maskCI, background: bgImage)
            }

            if let result = resultImage {
                return .success(result)
            } else {
                return .failure(BackgroundRemovalError.compositionFailed)
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Composition Methods

    private func applyTransparentBackground(original: CIImage, mask: CIImage) -> UIImage? {
        let transparent = CIImage(color: CIColor.clear).cropped(to: original.extent)
        return blend(foreground: original, background: transparent, mask: mask)
    }

    private func applySolidBackground(original: CIImage, mask: CIImage, color: UIColor) -> UIImage? {
        let colorImage = CIImage(color: CIColor(color: color)).cropped(to: original.extent)
        return blend(foreground: original, background: colorImage, mask: mask)
    }

    private func applyBlurredBackground(original: CIImage, mask: CIImage, radius: CGFloat) -> UIImage? {
        guard let blurred = CIFilter(
            name: "CIGaussianBlur",
            parameters: [kCIInputImageKey: original, kCIInputRadiusKey: radius]
        )?.outputImage?.cropped(to: original.extent) else { return nil }
        return blend(foreground: original, background: blurred, mask: mask)
    }

    private func applyCustomBackground(original: CIImage, mask: CIImage, background: UIImage) -> UIImage? {
        // 修正图片方向（相册照片可能带 EXIF 旋转标记）
        let normalizedBg = background.normalizedOrientation()
        guard let bgCG = normalizedBg.cgImage else { return nil }
        var bgCI = CIImage(cgImage: bgCG)

        // Scale background to match original image dimensions
        let scaleX = original.extent.width / bgCI.extent.width
        let scaleY = original.extent.height / bgCI.extent.height
        bgCI = bgCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        return blend(foreground: original, background: bgCI, mask: mask)
    }

    private func blend(foreground: CIImage, background: CIImage, mask: CIImage) -> UIImage? {
        // Scale mask to match image dimensions
        let scaleX = foreground.extent.width / mask.extent.width
        let scaleY = foreground.extent.height / mask.extent.height
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        filter.setValue(scaledMask, forKey: kCIInputMaskImageKey)

        guard let output = filter.outputImage,
              let cgResult = ciContext.createCGImage(output, from: foreground.extent) else {
            return nil
        }
        return UIImage(cgImage: cgResult)
    }
}

enum BackgroundRemovalError: LocalizedError {
    case invalidImage
    case noMaskGenerated
    case compositionFailed
    case notSupported

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid input image"
        case .noMaskGenerated: return "Failed to generate foreground mask"
        case .compositionFailed: return "Failed to compose final image"
        case .notSupported: return "Background removal requires iOS 17 or later"
        }
    }
}
