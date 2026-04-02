//
//  TextRemovalProcessor.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import Vision

final class TextRemovalProcessor: MaskBasedProcessor {

    let identifier = "text_removal"

    let toolDefinition = ToolDefinition(
        identifier: "text_removal",
        nameKey: "tool_text_removal",
        iconName: "textformat",
        tier: .free,
        moduleGroup: .removalRepair
    )

    private var lama: LaMaImageInpenting { LaMaImageInpenting.shared }

    var isReady: Bool { lama.lama != nil }

    func preload() {
        _ = LaMaImageInpenting.shared
    }

    func unload() {}

    func process(input: ProcessingInput, options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        completion(.failure(NSError(domain: "TextRemovalProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mask required"])))
    }

    func process(input: ProcessingInput, mask: UIImage, maskRects: [CGRect], options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        lama.inpent(image: input.image, mask: mask, inpaintingRects: maskRects) { outImage, error in
            if let outImage = outImage {
                completion(.success(outImage))
            } else if let error = error {
                completion(.failure(error))
            } else {
                completion(.failure(NSError(domain: "TextRemovalProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
            }
        }
    }

    /// Process multiple region clusters iteratively to preserve image quality.
    /// Each cluster is individually cropped → resized to 512 → inpainted → written back,
    /// preventing large-area downscaling that causes blurriness.
    func processIteratively(input: ProcessingInput, mask: UIImage, clusters: [[CGRect]], progress: ((Float) -> Void)?, completion: @escaping (ProcessingResult) -> Void) {
        lama.inpentIteratively(image: input.image, mask: mask, clusters: clusters, progress: progress) { outImage, error in
            if let outImage = outImage {
                completion(.success(outImage))
            } else if let error = error {
                completion(.failure(error))
            } else {
                completion(.failure(NSError(domain: "TextRemovalProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
            }
        }
    }

    func detectText(in image: UIImage) async throws -> [CGRect] {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "TextRemovalProcessor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                var detectedRects: [CGRect] = []

                for observation in observations {
                    let box = observation.boundingBox
                    // Convert normalized coordinates to image coordinates
                    let rect = CGRect(
                        x: box.origin.x * imageSize.width,
                        y: (1 - box.origin.y - box.height) * imageSize.height,
                        width: box.width * imageSize.width,
                        height: box.height * imageSize.height
                    )
                    detectedRects.append(rect)
                }

                continuation.resume(returning: detectedRects)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Support multiple languages to catch more text
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja", "ko"]
            // Lower minimum text height to detect smaller text (default ~1/32 of image)
            request.minimumTextHeight = 0.008

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
