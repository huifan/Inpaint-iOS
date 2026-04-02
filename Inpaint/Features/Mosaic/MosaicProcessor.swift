//
//  MosaicProcessor.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit
import CoreImage

enum MosaicType: String {
    case pixelate
    case gaussianBlur
    case crystallize
    case trianglePixelate
}

final class MosaicProcessor: MaskBasedProcessor {

    let identifier = "mosaic"

    let toolDefinition = ToolDefinition(
        identifier: "mosaic",
        nameKey: "tool_mosaic",
        iconName: "mosaic.fill",
        tier: .free,
        moduleGroup: .effectsCreative
    )

    var isReady: Bool { true } // No ML model needed

    func preload() {}
    func unload() {}

    func process(input: ProcessingInput, options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        completion(.failure(NSError(domain: "MosaicProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mask required"])))
    }

    func process(input: ProcessingInput, mask: UIImage, maskRects: [CGRect], options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        let mosaicType: MosaicType = options.value(for: "mosaicType") ?? .pixelate
        let intensity: CGFloat = options.value(for: "intensity") ?? 20.0

        DispatchQueue.global(qos: .userInitiated).async {
            guard let result = self.applyMosaic(
                to: input.image,
                mask: mask,
                rects: maskRects,
                type: mosaicType,
                intensity: intensity
            ) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MosaicProcessor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to apply mosaic"])))
                }
                return
            }
            DispatchQueue.main.async {
                completion(.success(result))
            }
        }
    }

    private func applyMosaic(to image: UIImage, mask: UIImage, rects: [CGRect], type: MosaicType, intensity: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let ciContext = CIContext()
        let ciImage = CIImage(cgImage: cgImage)

        // Apply the filter to the entire image
        let filtered: CIImage?
        switch type {
        case .pixelate:
            let filter = CIFilter(name: "CIPixellate")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(intensity, forKey: kCIInputScaleKey)
            filtered = filter?.outputImage
        case .gaussianBlur:
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(intensity, forKey: kCIInputRadiusKey)
            filtered = filter?.outputImage?.cropped(to: ciImage.extent)
        case .crystallize:
            let filter = CIFilter(name: "CICrystallize")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(intensity, forKey: "inputRadius")
            filtered = filter?.outputImage
        case .trianglePixelate:
            let filter = CIFilter(name: "CITriangleKaleidoscope")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(intensity, forKey: "inputSize")
            filtered = filter?.outputImage?.cropped(to: ciImage.extent)
        }

        guard let filteredImage = filtered else { return nil }

        // Create mask CIImage from the drawing (already at image size via exportAsGrayscaleImage(for:))
        guard let maskCG = mask.cgImage else { return nil }
        var scaledMask = CIImage(cgImage: maskCG)

        // Scale mask if dimensions don't match (fallback for legacy export)
        if abs(scaledMask.extent.width - ciImage.extent.width) > 1 ||
           abs(scaledMask.extent.height - ciImage.extent.height) > 1 {
            let scaleX = ciImage.extent.width / scaledMask.extent.width
            let scaleY = ciImage.extent.height / scaledMask.extent.height
            scaledMask = scaledMask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        // Blend: where mask is white → show filtered, where black → show original
        let blendFilter = CIFilter(name: "CIBlendWithMask")
        blendFilter?.setValue(filteredImage, forKey: kCIInputImageKey)
        blendFilter?.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
        blendFilter?.setValue(scaledMask, forKey: kCIInputMaskImageKey)

        guard let output = blendFilter?.outputImage,
              let outputCG = ciContext.createCGImage(output, from: ciImage.extent) else { return nil }

        return UIImage(cgImage: outputCG)
    }
}
