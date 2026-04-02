//
//  RealESRGANHelper.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import CoreML

/// Helper class for Real-ESRGAN super-resolution CoreML inference.
/// Requires RealESRGAN_x2_FP16.mlpackage and/or RealESRGAN_x4_FP16.mlpackage
/// models to be added to the project.
final class RealESRGANHelper {

    enum Scale: Int {
        case x2 = 2
        case x4 = 4
    }

    enum RealESRGANError: LocalizedError {
        case modelNotAvailable
        case inferenceFailed
        case invalidInput
        case bufferConversionFailed

        var errorDescription: String? {
            switch self {
            case .modelNotAvailable: return "Real-ESRGAN model not available"
            case .inferenceFailed: return "Super-resolution inference failed"
            case .invalidInput: return "Invalid input image"
            case .bufferConversionFailed: return "Failed to convert image to pixel buffer"
            }
        }
    }

    private var model2x: MLModel?
    private var model4x: MLModel?

    private let config: MLModelConfiguration = {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        return config
    }()

    static let shared = RealESRGANHelper()

    private init() {}

    /// Load the model for the specified scale.
    /// - Parameter scale: Upscaling factor (2 or 4)
    /// - Returns: Loaded model, or nil if not available
    func loadModel(scale: Scale) -> MLModel? {
        switch scale {
        case .x2:
            if model2x == nil {
                model2x = try? loadModel(named: "RealESRGAN_x2_FP16")
            }
            return model2x
        case .x4:
            if model4x == nil {
                model4x = try? loadModel(named: "RealESRGAN_x4_FP16")
            }
            return model4x
        }
    }

    private func loadModel(named name: String) throws -> MLModel {
        guard let modelURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") else {
            throw RealESRGANError.modelNotAvailable
        }
        let compiledModel = try MLModel(contentsOf: modelURL, configuration: config)
        return compiledModel
    }

    /// Check if models are available for the given scale.
    func isModelAvailable(scale: Scale) -> Bool {
        return loadModel(scale: scale) != nil
    }

    /// Run super-resolution inference on a single tile.
    /// - Parameters:
    ///   - image: Input image (should be tileSize x tileSize)
    ///   - scale: Upscaling factor
    /// - Returns: Upscaled image, or nil on failure
    func runInference(on image: UIImage, scale: Scale) -> UIImage? {
        guard let model = loadModel(scale: scale) else {
            return nil
        }

        guard let pixelBuffer = image.toPixelBuffer(
            width: Int(image.size.width),
            height: Int(image.size.height),
            pixelFormat: kCVPixelFormatType_32ARGB
        ) else {
            return nil
        }

        guard let inputFeature = try? MLFeatureValue(pixelBuffer: pixelBuffer) else {
            return nil
        }

        // Get input and output names from model description
        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outputName = model.modelDescription.outputDescriptionsByName.keys.first ?? "output"

        // Create feature provider manually
        let features: [String: MLFeatureValue] = [inputName: inputFeature]

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: features) else {
            return nil
        }

        do {
            let prediction = try model.prediction(from: provider)

            guard let outputFeature = prediction.featureValue(for: outputName),
                  let outputBuffer = outputFeature.imageBufferValue else {
                return nil
            }

            return outputBuffer.toUIImage()
        } catch {
            print("RealESRGAN inference error: \(error)")
            return nil
        }
    }
}

// MARK: - Pixel Buffer Conversions

extension UIImage {
    /// Convert UIImage to CVPixelBuffer with specified format and dimensions.
    func toPixelBuffer(width: Int, height: Int, pixelFormat: OSType) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        guard let cgImage = self.cgImage else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

extension CVPixelBuffer {
    /// Convert CVPixelBuffer to UIImage.
    func toUIImage() -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
