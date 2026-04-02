//
//  FilterProcessor.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import CoreImage

final class FilterProcessor: ImageProcessor {

    let identifier = "photo_filter"

    let toolDefinition = ToolDefinition(
        identifier: "photo_filter",
        nameKey: "tool_photo_filter",
        iconName: "camera.filters",
        tier: .free,
        moduleGroup: .effectsCreative
    )

    var isReady: Bool { true }

    private let context = CIContext()

    func preload() {}

    func unload() {}

    func process(input: ProcessingInput, options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        guard let filterID: String = options.value(for: "filterID"),
              let intensity: Float = options.value(for: "intensity") else {
            completion(.failure(NSError(domain: "FilterProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing filterID or intensity"])))
            return
        }

        guard let filterDef = FilterDefinition.allFilters.first(where: { $0.identifier == filterID }) else {
            completion(.failure(NSError(domain: "FilterProcessor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unknown filter"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let outputImage: UIImage?

            if filterDef.filters.isEmpty {
                outputImage = input.image
            } else {
                outputImage = self.applyFilters(filterDef.filters, to: input.image, intensity: intensity)
            }

            DispatchQueue.main.async {
                if let output = outputImage {
                    completion(.success(output))
                } else {
                    completion(.failure(NSError(domain: "FilterProcessor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Filter processing failed"])))
                }
            }
        }
    }

    private func applyFilters(_ filters: [(name: String, parameters: [String: Any])], to image: UIImage, intensity: Float) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        var processedImage = ciImage

        for (filterName, parameters) in filters {
            guard let filter = CIFilter(name: filterName) else { continue }
            filter.setValue(processedImage, forKey: kCIInputImageKey)

            for (key, value) in parameters {
                filter.setValue(value, forKey: key)
            }

            if let output = filter.outputImage {
                processedImage = output
            }
        }

        // Apply intensity blending with original
        if intensity < 1.0, let outputCGImage = context.createCGImage(processedImage, from: processedImage.extent) {
            let filteredImage = UIImage(cgImage: outputCGImage)
            return blendImages(original: image, filtered: filteredImage, intensity: CGFloat(intensity))
        }

        guard let outputCGImage = context.createCGImage(processedImage, from: processedImage.extent) else { return nil }
        return UIImage(cgImage: outputCGImage)
    }

    private func blendImages(original: UIImage, filtered: UIImage, intensity: CGFloat) -> UIImage? {
        let size = original.size
        UIGraphicsBeginImageContextWithOptions(size, false, original.scale)
        defer { UIGraphicsEndImageContext() }

        original.draw(in: CGRect(origin: .zero, size: size))

        if let context = UIGraphicsGetCurrentContext() {
            context.setBlendMode(.normal)
            context.setAlpha(1.0 - intensity)
            filtered.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: intensity)
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    func generateThumbnail(for filterID: String, size: CGSize = CGSize(width: 120, height: 120)) -> UIImage? {
        // Return a placeholder - actual thumbnails are generated in the view controller
        return nil
    }
}
