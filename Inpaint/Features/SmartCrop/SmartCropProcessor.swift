//
//  SmartCropProcessor.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import Vision

final class SmartCropProcessor: ImageProcessor {

    let identifier = "smart_crop"

    let toolDefinition = ToolDefinition(
        identifier: "smart_crop",
        nameKey: "tool_smart_crop",
        iconName: "crop",
        tier: .free,
        moduleGroup: .effectsCreative
    )

    var isReady: Bool { true }

    func preload() {}
    func unload() {}

    func process(input: ProcessingInput, options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        guard let cropRect: CGRect = options.value(for: "cropRect") else {
            completion(.failure(NSError(domain: "SmartCropProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing cropRect"])))
            return
        }

        guard let cgImage = input.image.cgImage else {
            completion(.failure(NSError(domain: "SmartCropProcessor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let croppedImage = input.image.crop(to: cropRect)
            DispatchQueue.main.async {
                completion(.success(croppedImage))
            }
        }
    }

    func detectSaliency(in image: UIImage) async throws -> CGRect {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "SmartCropProcessor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNSaliencyImageObservation],
                      let saliencyMap = observations.first else {
                    continuation.resume(returning: .zero)
                    return
                }

                // Get the most salient region
                if let salientObject = saliencyMap.salientObjects?.first {
                    continuation.resume(returning: salientObject.boundingBox)
                } else {
                    continuation.resume(returning: .zero)
                }
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func detectFaces(in image: UIImage) async throws -> [CGRect] {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "SmartCropProcessor", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                let faceRects = observations.map { observation -> CGRect in
                    let box = observation.boundingBox
                    return CGRect(
                        x: box.origin.x * imageSize.width,
                        y: (1 - box.origin.y - box.height) * imageSize.height,
                        width: box.width * imageSize.width,
                        height: box.height * imageSize.height
                    )
                }

                continuation.resume(returning: faceRects)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func computeRecommendedCrop(for imageSize: CGSize, targetAspectRatio: CGFloat?) -> CGRect {
        // Default to full image with padding
        let padding: CGFloat = 0.1
        return CGRect(
            x: imageSize.width * padding,
            y: imageSize.height * padding,
            width: imageSize.width * (1 - 2 * padding),
            height: imageSize.height * (1 - 2 * padding)
        )
    }
}
