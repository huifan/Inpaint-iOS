//
//  EnhancementProcessor.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import CoreImage

final class EnhancementProcessor: ImageProcessor {

    let identifier = "image_enhance"

    let toolDefinition = ToolDefinition(
        identifier: "image_enhance",
        nameKey: "tool_image_enhance",
        iconName: "wand.and.stars",
        tier: .free,
        moduleGroup: .enhancement
    )

    private let ciContext = CIContext()
    private let srHelper = RealESRGANHelper.shared

    var isReady: Bool { true }

    func preload() {}

    func unload() {}

    func process(
        input: ProcessingInput,
        options: ProcessingOptions,
        completion: @escaping (ProcessingResult) -> Void
    ) {
        processWithProgress(input: input, options: options, progress: nil, completion: completion)
    }

    /// Process with optional progress callback for SR operations.
    func processWithProgress(
        input: ProcessingInput,
        options: ProcessingOptions,
        progress: ((Float) -> Void)?,
        completion: @escaping (ProcessingResult) -> Void
    ) {
        let mode: EnhancementMode = options.value(for: "enhancementMode") ?? .autoEnhance

        DispatchQueue.global(qos: .userInitiated).async {
            let result: UIImage?

            switch mode {
            case .autoEnhance:
                result = self.applyAutoEnhance(to: input.image)
            case .denoise:
                result = self.applyDenoise(to: input.image)
            case .superResolution2x:
                result = self.applySuperResolution(to: input.image, scale: 2, progress: progress)
            case .superResolution4x:
                result = self.applySuperResolution(to: input.image, scale: 4, progress: progress)
            }

            DispatchQueue.main.async {
                if let result {
                    completion(.success(result))
                } else {
                    completion(.failure(EnhancementError.processingFailed))
                }
            }
        }
    }

    // MARK: - Auto Enhance

    private func applyAutoEnhance(to image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        var ciImage = CIImage(cgImage: cgImage)

        // Apply all auto adjustment filters
        let adjustments = ciImage.autoAdjustmentFilters()
        for filter in adjustments {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                ciImage = output
            }
        }

        guard let outputCG = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: outputCG)
    }

    // MARK: - Denoise

    private func applyDenoise(to image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CINoiseReduction") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.02, forKey: "inputNoiseLevel")
        filter.setValue(0.40, forKey: "inputSharpness")

        guard let output = filter.outputImage,
              let outputCG = ciContext.createCGImage(output, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: outputCG)
    }

    // MARK: - Super Resolution

    /// Super-resolution processing using tile-based approach with Real-ESRGAN.
    /// Falls back to bicubic upscaling if models are not available.
    func applySuperResolution(
        to image: UIImage,
        scale: Int,
        progress: ((Float) -> Void)? = nil
    ) -> UIImage? {
        let srScale = scale == 2 ? RealESRGANHelper.Scale.x2 : RealESRGANHelper.Scale.x4

        if srHelper.isModelAvailable(scale: srScale) {
            return applyRealESRGAN(to: image, scale: scale, progress: progress)
        } else {
            return applyBicubicUpscale(to: image, scale: scale)
        }
    }

    /// Apply Real-ESRGAN super-resolution with tile-based processing.
    private func applyRealESRGAN(
        to image: UIImage,
        scale: Int,
        progress: ((Float) -> Void)? = nil
    ) -> UIImage? {
        let srScale = scale == 2 ? RealESRGANHelper.Scale.x2 : RealESRGANHelper.Scale.x4

        // Use 256 tiles for SR processing
        let config = TileProcessor.Config(
            tileSize: 256,
            overlap: 16,
            scaleFactor: scale
        )

        // Check available memory and limit image size if needed
        let maxDimension: CGFloat = 2048
        var processedImage = image

        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scaleRatio = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let newSize = CGSize(
                width: image.size.width * scaleRatio,
                height: image.size.height * scaleRatio
            )
            if let resized = image.scaled(to: newSize) {
                processedImage = resized
            }
        }

        return TileProcessor.process(
            image: processedImage,
            config: config,
            processTile: { [weak self] tile in
                return self?.srHelper.runInference(on: tile, scale: srScale)
            },
            progress: progress
        )
    }

    /// Fallback bicubic upscaling when ML models are not available.
    private func applyBicubicUpscale(to image: UIImage, scale: Int) -> UIImage? {
        let newSize = CGSize(
            width: image.size.width * CGFloat(scale),
            height: image.size.height * CGFloat(scale)
        )

        guard let cgImage = image.cgImage else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: newSize))

        guard let outputCG = context.makeImage() else { return nil }
        return UIImage(cgImage: outputCG)
    }
}

enum EnhancementError: LocalizedError {
    case processingFailed
    case modelNotAvailable

    var errorDescription: String? {
        switch self {
        case .processingFailed: return "Image enhancement failed"
        case .modelNotAvailable: return "Enhancement model not available"
        }
    }
}
