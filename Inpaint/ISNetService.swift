//
//  ISNetService.swift
//  Inpaint
//
//  ISNet image segmentation service using ONNX Runtime iOS.
//  Input: UIImage (any size)
//  Output: UIImage mask (alpha channel, white=subject, black=background)
//

import UIKit
import ONNXRuntime

class ISNetService {

    static let shared = ISNetService()

    private var session: ORTSession?
    private let workQueue = DispatchQueue(label: "ISNetService")

    // ISNet model expects input/output names
    private let inputName = "input_image"
    private let outputName = "output_image"

    // Target model input size (1024x1024 for ISNet)
    private let modelSize: Int = 1024

    private init() {
        preload()
    }

    func preload() {
        workQueue.async { [weak self] in
            self?.loadModel()
        }
    }

    private func loadModel() {
        guard let modelPath = Bundle.main.path(forResource: "isnet-general-use", ofType: "onnx") else {
            print("[ISNet] ERROR: isnet-general-use.onnx not found in bundle")
            return
        }

        do {
            let env = ORTEnv()
            session = try ORTSession(env: env, modelPath: modelPath)
            print("[ISNet] Model loaded successfully")
        } catch {
            print("[ISNet] ERROR loading model: \(error)")
        }
    }

    /// Predict mask for input image.
    /// - Parameter inputImage: Source UIImage
    /// - Returns: Grayscale mask UIImage (white=subject, black=background), or nil on failure
    func predict(inputImage: UIImage) -> UIImage? {
        guard let session = session else {
            print("[ISNet] Session not ready")
            return nil
        }

        // 1. Resize to model input size
        guard let resized = inputImage.resized(to: CGSize(width: modelSize, height: modelSize)) else {
            print("[ISNet] Failed to resize image")
            return nil
        }

        // 2. Convert to RGB float tensor [1, 3, H, W] with values [0, 1]
        guard let rgbTensor = resized.rgbFloat32Tensor(shape: [1, 3, modelSize, modelSize]) else {
            print("[ISNet] Failed to create RGB tensor")
            return nil
        }

        // 3. Run inference
        do {
            let output = try session.run(
                inputNames: [inputName],
                inputTensors: [inputName: rgbTensor],
                outputNames: [outputName]
            )

            guard let outputValue = output[outputName] else {
                print("[ISNet] No output named '\(outputName)'")
                return nil
            }

            // 4. output shape: [1, 1, H, W], data is Float32 [0, 1]
            let maskData = outputValue.float32Data
            let maskWidth = outputValue.shape?[3] ?? modelSize
            let maskHeight = outputValue.shape?[2] ?? modelSize

            // 5. Convert Float32 mask → UIImage (grayscale)
            guard let maskImage = UIImage.fromGrayFloat32(
                Array(maskData),
                width: Int(maskWidth),
                height: Int(maskHeight)
            ) else {
                print("[ISNet] Failed to create mask image")
                return nil
            }

            return maskImage

        } catch {
            print("[ISNet] Inference error: \(error)")
            return nil
        }
    }

    /// Async version of predict
    func predictAsync(inputImage: UIImage, completion: @escaping (UIImage?) -> Void) {
        workQueue.async { [weak self] in
            let result = self?.predict(inputImage: inputImage)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}

// MARK: - UIImage Extensions

extension UIImage {

    /// Resize image to target size.
    func resized(to targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Convert UIImage to Float32 RGB tensor with shape [B, C, H, W], values in [0, 1].
    /// - Parameter shape: [batch, channels, height, width]
    /// - Returns: ORTValue tensor ready for ONNX Runtime
    func rgbFloat32Tensor(shape: [NSNumber]) -> ORTValue? {
        guard let cgImage = self.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelBytes = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Build [0,1] float32 array in CHW format (R then G then B)
        let channelCount = 3
        let totalFloats = shape[0].intValue * shape[1].intValue * shape[2].intValue * shape[3].intValue
        var floatData = [Float32](repeating: 0, count: totalFloats)

        let h = shape[2].intValue
        let w = shape[3].intValue

        // R channel
        for y in 0..<min(height, h) {
            for x in 0..<min(width, w) {
                let pixelIdx = (y * width + x) * bytesPerPixel
                let flatIdx = y * w + x  // CHW: R channel first
                floatData[flatIdx] = Float32(pixelBytes[pixelIdx]) / 255.0
            }
        }
        // G channel
        for y in 0..<min(height, h) {
            for x in 0..<min(width, w) {
                let pixelIdx = (y * width + x) * bytesPerPixel
                let flatIdx = h * w + y * w + x  // R plane + G plane
                floatData[flatIdx] = Float32(pixelBytes[pixelIdx + 1]) / 255.0
            }
        }
        // B channel
        for y in 0..<min(height, h) {
            for x in 0..<min(width, w) {
                let pixelIdx = (y * width + x) * bytesPerPixel
                let flatIdx = 2 * h * w + y * w + x  // R + G + B
                floatData[flatIdx] = Float32(pixelBytes[pixelIdx + 2]) / 255.0
            }
        }

        do {
            let data = Data(bytes: &floatData, count: totalFloats * MemoryLayout<Float32>.size)
            return try ORTValue(tensorData: data, elementType: .float32, shape: shape)
        } catch {
            print("[ISNet] ORTValue creation failed: \(error)")
            return nil
        }
    }

    /// Create grayscale UIImage from Float32 array [0, 1].
    static func fromGrayFloat32(_ data: [Float32], width: Int, height: Int) -> UIImage? {
        var byteData = [UInt8](repeating: 0, count: width * height)
        for i in 0..<min(data.count, width * height) {
            byteData[i] = UInt8(min(255, max(0, data[i] * 255)))
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(byteData) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: [],
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
