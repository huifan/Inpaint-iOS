//
//  SAMSegmentHelper.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import Vision
import CoreML

/// Helper class for Segment Anything Model (SAM) point-based segmentation.
/// Generates masks for objects based on user tap points.
final class SAMSegmentHelper {

    enum SAMError: LocalizedError {
        case modelNotAvailable
        case encodingFailed
        case decodingFailed
        case noMaskGenerated

        var errorDescription: String? {
            switch self {
            case .modelNotAvailable: return "SAM model not available"
            case .encodingFailed: return "Failed to encode image for SAM"
            case .decodingFailed: return "Failed to decode SAM mask"
            case .noMaskGenerated: return "No mask generated"
            }
        }
    }

    /// Single tap point with label (foreground/background)
    struct TapPoint {
        let point: CGPoint
        let isForeground: Bool  // true = tap to select, false = tap to deselect

        static func foreground(at point: CGPoint) -> TapPoint {
            TapPoint(point: point, isForeground: true)
        }
    }

    private var cachedEmbedding: MLMultiArray?
    private var cachedImageSize: CGSize?

    static let shared = SAMSegmentHelper()

    private init() {}

    /// Check if SAM models are available.
    var isAvailable: Bool {
        // When SAM models are added to the project, check for them here
        // For now, return false to indicate SAM is not yet integrated
        return false
    }

    /// Pre-compute image embedding for faster subsequent segmentation.
    /// Call this once when the image is loaded.
    func encodeImage(_ image: UIImage) async throws {
        guard isAvailable else {
            throw SAMError.modelNotAvailable
        }

        // TODO: When SAM model is available:
        // 1. Resize image to 1024x1024
        // 2. Run SAM image encoder
        // 3. Cache the embedding

        cachedImageSize = image.size
    }

    /// Generate a mask for the object at the given point.
    /// - Parameters:
    ///   - tapPoint: User tap point in image coordinates
    ///   - imageSize: Original image size
    /// - Returns: Binary mask as UIImage (white = foreground)
    func segment(at tapPoint: TapPoint, imageSize: CGSize) async throws -> UIImage {
        guard isAvailable else {
            throw SAMError.modelNotAvailable
        }

        // TODO: When SAM model is available:
        // 1. Normalize tap point to [0, 1] range
        // 2. Create prompt with point coordinates and label
        // 3. Run SAM mask decoder with cached embedding
        // 4. Return generated mask as UIImage

        throw SAMError.modelNotAvailable
    }

    /// Clear cached embedding to free memory.
    func clearCache() {
        cachedEmbedding = nil
        cachedImageSize = nil
    }

    /// Convert normalized Vision bounding box to image coordinates.
    func convertBox(_ normalizedBox: CGRect, to imageSize: CGSize) -> CGRect {
        let width = normalizedBox.width * imageSize.width
        let height = normalizedBox.height * imageSize.height
        let x = normalizedBox.origin.x * imageSize.width
        let y = (1 - normalizedBox.origin.y - normalizedBox.height) * imageSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Vision-based Alternative

/// Alternative segmentation using Vision's built-in capabilities
/// when SAM is not available.
extension SAMSegmentHelper {

    /// Use Vision's saliency detection as a fallback when SAM is not available.
    /// - Parameters:
    ///   - image: Input image
    ///   - point: Tap point in image coordinates
    /// - Returns: Saliency-based mask if available
    func generateSaliencyMask(for image: UIImage, near point: CGPoint) async throws -> UIImage? {
        guard let cgImage = image.cgImage else {
            throw SAMError.encodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result = request.results?.first as? VNSaliencyImageObservation else {
                    continuation.resume(returning: nil)
                    return
                }

                // Get salient objects
                guard let salientObjects = result.salientObjects, !salientObjects.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Find the object closest to the tap point
                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                let normalizedPoint = CGPoint(
                    x: point.x / imageSize.width,
                    y: point.y / imageSize.height
                )

                var closestObject: VNRectangleObservation?
                var minDistance: CGFloat = .greatestFiniteMagnitude

                for object in salientObjects {
                    let center = CGPoint(
                        x: object.boundingBox.midX,
                        y: object.boundingBox.midY
                    )
                    let distance = hypot(normalizedPoint.x - center.x, normalizedPoint.y - center.y)
                    if distance < minDistance {
                        minDistance = distance
                        closestObject = object
                    }
                }

                if let object = closestObject {
                    // Convert bounding box to mask
                    let maskRect = self.convertBox(object.boundingBox, to: imageSize)
                    let mask = self.createMaskImage(from: maskRect, size: imageSize)
                    continuation.resume(returning: mask)
                } else {
                    continuation.resume(returning: nil)
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

    /// Create a binary mask image from a rectangle.
    private func createMaskImage(from rect: CGRect, size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Fill with black (background)
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        // Fill rectangle with white (foreground)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
