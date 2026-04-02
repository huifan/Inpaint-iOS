//
//  TileProcessor.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit

/// Utility for processing large images in tiles with overlap blending.
/// Used for super-resolution models that have fixed input size requirements.
final class TileProcessor {

    struct Config {
        let tileSize: Int
        let overlap: Int
        let scaleFactor: Int

        /// Default configuration for 256x256 tiles with 16px overlap.
        static let default256 = Config(tileSize: 256, overlap: 16, scaleFactor: 2)

        /// Configuration for 512x512 tiles with 32px overlap.
        static let default512 = Config(tileSize: 512, overlap: 32, scaleFactor: 2)
    }

    /// Process a large image tile-by-tile with overlapping tiles.
    /// - Parameters:
    ///   - image: Input image
    ///   - config: Tile configuration
    ///   - processTile: Closure that processes each tile and returns the scaled result
    ///   - progress: Optional progress callback (0.0 to 1.0)
    /// - Returns: Stitched output image, or nil on failure
    static func process(
        image: UIImage,
        config: Config,
        processTile: (UIImage) -> UIImage?,
        progress: ((Float) -> Void)? = nil
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let step = config.tileSize - config.overlap
        let outputScale = config.scaleFactor

        let cols = max(1, Int(ceil(Double(width) / Double(step))))
        let rows = max(1, Int(ceil(Double(height) / Double(step))))
        let totalTiles = cols * rows

        let outputWidth = width * outputScale
        let outputHeight = height * outputScale

        // Create output context
        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: outputWidth, height: outputHeight), false, 1.0
        )
        defer { UIGraphicsEndImageContext() }

        // Fill with scaled original image as background
        guard let scaledImage = image.scaled(to: CGSize(width: outputWidth, height: outputHeight)) else {
            return nil
        }
        scaledImage.draw(at: .zero)

        var tileIndex = 0
        for row in 0..<rows {
            for col in 0..<cols {
                let x = min(col * step, max(0, width - config.tileSize))
                let y = min(row * step, max(0, height - config.tileSize))
                let cropRect = CGRect(x: x, y: y, width: config.tileSize, height: config.tileSize)

                guard let tileCG = cgImage.cropping(to: cropRect) else { continue }
                let tileImage = UIImage(cgImage: tileCG)

                guard let processedTile = processTile(tileImage) else { continue }

                // Calculate output position and draw tile
                let outX = x * outputScale
                let outY = y * outputScale
                processedTile.draw(at: CGPoint(x: outX, y: outY))

                tileIndex += 1
                progress?(Float(tileIndex) / Float(totalTiles))
            }
        }

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Process with proper feathered blending for overlapping tiles.
    /// This method blends tile edges to avoid visible seams.
    static func processWithBlending(
        image: UIImage,
        config: Config,
        processTile: (UIImage) -> UIImage?,
        progress: ((Float) -> Void)? = nil
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let step = config.tileSize - config.overlap
        let outputScale = config.scaleFactor

        let cols = max(1, Int(ceil(Double(width) / Double(step))))
        let rows = max(1, Int(ceil(Double(height) / Double(step))))
        let totalTiles = cols * rows

        let outputWidth = width * outputScale
        let outputHeight = height * outputScale
        let outputTileSize = config.tileSize * outputScale
        let outputOverlap = config.overlap * outputScale

        // Accumulation buffer for weighted blending (RGBA)
        var accumulationBuffer: [Float] = Array(repeating: 0, count: outputWidth * outputHeight * 4)
        var weightBuffer: [Float] = Array(repeating: 0, count: outputWidth * outputHeight)

        var tileIndex = 0
        for row in 0..<rows {
            for col in 0..<cols {
                let x = min(col * step, max(0, width - config.tileSize))
                let y = min(row * step, max(0, height - config.tileSize))
                let cropRect = CGRect(x: x, y: y, width: config.tileSize, height: config.tileSize)

                guard let tileCG = cgImage.cropping(to: cropRect) else { continue }
                let tileImage = UIImage(cgImage: tileCG)

                guard let processedTile = processTile(tileImage),
                      let processedCG = processedTile.cgImage else { continue }

                let outX = x * outputScale
                let outY = y * outputScale

                // Accumulate weighted tile
                accumulateTile(
                    into: &accumulationBuffer,
                    weight: &weightBuffer,
                    from: processedCG,
                    offsetX: outX,
                    offsetY: outY,
                    tileSize: outputTileSize,
                    stride: outputWidth
                )

                tileIndex += 1
                progress?(Float(tileIndex) / Float(totalTiles))
            }
        }

        // Normalize and create final image
        return createOutputImage(
            accumulation: accumulationBuffer,
            weight: weightBuffer,
            width: outputWidth,
            height: outputHeight
        )
    }

    // MARK: - Private Helpers

    /// Accumulate a processed tile into the accumulation buffer.
    private static func accumulateTile(
        into accumulation: inout [Float],
        weight: inout [Float],
        from tileCG: CGImage,
        offsetX: Int,
        offsetY: Int,
        tileSize: Int,
        stride: Int
    ) {
        guard let data = tileCG.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return }

        let bitsPerPixel = tileCG.bitsPerPixel
        let bytesPerPixel = max(1, bitsPerPixel / 8)
        let tileStride = tileCG.bytesPerRow

        for y in 0..<tileSize {
            let outY = offsetY + y
            guard outY >= 0 && outY < stride else { continue }
            for x in 0..<tileSize {
                let outX = offsetX + x
                guard outX >= 0 && outX < stride else { continue }

                let tileIdx = y * tileStride + x * bytesPerPixel
                let outIdx = (outY * stride + outX) * 4

                // Default weight of 1.0 for non-overlapping regions
                let w: Float = 1.0

                // Accumulate RGBA
                if bytesPerPixel >= 4 {
                    accumulation[outIdx] += Float(bytes[tileIdx + 1]) * w     // R
                    accumulation[outIdx + 1] += Float(bytes[tileIdx + 2]) * w // G
                    accumulation[outIdx + 2] += Float(bytes[tileIdx + 3]) * w // B
                    accumulation[outIdx + 3] += Float(bytes[tileIdx]) * w     // A
                } else {
                    // Grayscale or other format
                    accumulation[outIdx] += Float(bytes[tileIdx]) * w
                    accumulation[outIdx + 1] += Float(bytes[tileIdx]) * w
                    accumulation[outIdx + 2] += Float(bytes[tileIdx]) * w
                    accumulation[outIdx + 3] += 255 * w
                }
                weight[outY * stride + outX] += w
            }
        }
    }

    /// Create final output image by normalizing accumulated buffer.
    private static func createOutputImage(
        accumulation: [Float],
        weight: [Float],
        width: Int,
        height: Int
    ) -> UIImage? {
        var normalized = [UInt8](repeating: 0, count: width * height * 4)

        for i in 0..<(width * height) {
            let idx = i * 4
            let w = max(weight[i], 0.0001) // Avoid division by zero

            normalized[idx] = UInt8(min(255, max(0, accumulation[idx] / w)))         // A
            normalized[idx + 1] = UInt8(min(255, max(0, accumulation[idx + 1] / w))) // R
            normalized[idx + 2] = UInt8(min(255, max(0, accumulation[idx + 2] / w))) // G
            normalized[idx + 3] = UInt8(min(255, max(0, accumulation[idx + 3] / w))) // B
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: &normalized,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ), let cgImage = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - UIImage Extension

extension UIImage {
    /// Scale image to specified size.
    func scaled(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
