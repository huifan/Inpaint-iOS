//
//  FaceDetectionHelper.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import Vision

final class FaceDetectionHelper {

    enum FaceDetectionError: Error {
        case invalidImage
        case detectionFailed
    }

    /// Detect all faces in an image and return their bounding boxes.
    /// - Parameter image: Input UIImage
    /// - Returns: Array of CGRect in normalized coordinates [0,1]
    static func detectFaces(in image: UIImage) async throws -> [CGRect] {
        guard let cgImage = image.cgImage else {
            throw FaceDetectionError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let boxes = (request.results as? [VNFaceObservation])?.map { $0.boundingBox } ?? []
                continuation.resume(returning: boxes)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Convert normalized Vision bounding box to image coordinates.
    /// - Parameters:
    ///   - normalizedBox: Box in normalized coordinates (0-1)
    ///   - imageSize: Size of the original image
    /// - Returns: CGRect in image coordinate space (origin at top-left)
    static func convertBox(_ normalizedBox: CGRect, to imageSize: CGSize) -> CGRect {
        let width = normalizedBox.width * imageSize.width
        let height = normalizedBox.height * imageSize.height
        let x = normalizedBox.origin.x * imageSize.width
        let y = (1 - normalizedBox.origin.y - normalizedBox.height) * imageSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Convert normalized face boxes to mask rectangles with padding.
    /// - Parameters:
    ///   - normalizedBoxes: Face boxes in normalized coords
    ///   - imageSize: Original image size
    ///   - padding: Extra padding around face (as fraction of face size)
    /// - Returns: Array of CGRect in image coordinate space
    static func faceMaskRects(
        from normalizedBoxes: [CGRect],
        imageSize: CGSize,
        padding: CGFloat = 0.2
    ) -> [CGRect] {
        normalizedBoxes.map { box in
            let rect = convertBox(box, to: imageSize)
            let horizontalPadding = rect.width * max(padding, 0.35)
            let topPadding = rect.height * max(padding * 1.4, 0.45)
            let bottomPadding = rect.height * max(padding * 0.8, 0.2)

            let expanded = CGRect(
                x: rect.minX - horizontalPadding,
                y: rect.minY - topPadding,
                width: rect.width + horizontalPadding * 2,
                height: rect.height + topPadding + bottomPadding
            )

            return expanded.intersection(CGRect(origin: .zero, size: imageSize))
        }
    }
}
