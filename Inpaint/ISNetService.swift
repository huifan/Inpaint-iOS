//
//  ISNetService.swift
//  Inpaint
//
//  ISNet auto-segmentation service for Inpaint-iOS.
//  Wraps ISNetWrapper (Objective-C++ / ONNX Runtime C API).
//
//  SETUP STEPS:
//  ============
//
//  Step 1: Download ONNX Runtime iOS Framework
//  -------------------------------------------
//  Option A (Recommended): GitHub Release
//    1. Go to: https://github.com/microsoft/onnxruntime/releases
//    2. Download: onnxruntime-ios-xcframework-*.zip (latest version)
//       Example: onnxruntime-ios-xcframework-1.24.3.zip (~50MB)
//    3. Extract -> ONNXRuntime.xcframework
//    4. Drag ONNXRuntime.xcframework into Xcode project
//       - Copy items if needed
//       - Destination: Inpaint target
//    5. Build Phases -> Link Binary With Libraries:
//       Add: libc++abi.tbd, Accelerate.framework, CoreML.framework
//
//  Option B: CocoaPods (onnxruntime-c) - ALREADY CONFIGURED
//    Podfile has: pod 'onnxruntime-c', '~> 1.24'
//    Run: pod install
//
//  Step 2: Add Model File
//  ----------------------
//  1. Download model from rembg cache:
//     cp ~/.u2net/isnet-general-use.onnx ~/Inpaint-iOS/Inpaint/
//  2. Drag Inpaint/isnet-general-use.onnx into Xcode
//     - Copy items if needed
//     - Destination: Inpaint target
//
//  Step 3: Create Bridging Header
//  ------------------------------------------------
//  Inpaint-Bridging-Header.h already created and configured
//
//  Step 4: Build & Run
//  -------------------
//  open Inpaint.xcworkspace -> Run on iPhone
//

import UIKit

/// Result wrapper for Swift callers.
class ISNetPredictionResult {
    var maskImage: UIImage?
    var success: Bool = false
    var error: Error?
}

/// Swift service wrapping the Objective-C++ ISNetWrapper.
/// This is the interface used by InpaintingViewController.
class ISNetService {
    
    static let shared = ISNetService()
    
    private let wrapper: ISNetWrapper
    private var isLoaded: Bool = false
    private let workQueue = DispatchQueue(label: "ISNetService", qos: .userInitiated)
    
    /// Model input size (ISNet: 1024x1024)
    static let modelInputSize: Int = 1024
    
    private init() {
        wrapper = ISNetWrapper.shared()
    }
    
    /// Preload model. Call at app startup (e.g., in AppDelegate).
    func preload() {
        workQueue.async { [weak self] in
            self?.loadModel()
        }
    }
    
    private func loadModel() {
        // Try to load model, silently fail if not found (will retry at predict time)
        do {
            try wrapper.loadModel("isnet-general-use")
            isLoaded = true
            print("[ISNet] Model loaded successfully")
        } catch {
            print("[ISNet] Model load failed: \(error)")
        }
    }
    
    /// Synchronous mask prediction.
    /// Returns: grayscale mask (white=subject, black=background), or nil on failure.
    func predict(inputImage: UIImage) -> UIImage? {
        if !isLoaded {
            do {
                try wrapper.loadModel("isnet-general-use")
                isLoaded = true
            } catch {
                print("[ISNet] Model not available: \(error)")
                return nil
            }
        }
        
        do {
            return try wrapper.predict(inputImage)
        } catch {
            print("[ISNet] Prediction failed: \(error)")
            return nil
        }
    }
    
    /// Async mask prediction (background thread, result on main queue).
    func predictAsync(inputImage: UIImage, completion: @escaping (ISNetPredictionResult) -> Void) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            
            var result = ISNetPredictionResult()
            
            // Load model if not yet loaded
            if !self.isLoaded {
                do {
                    try self.wrapper.loadModel("isnet-general-use")
                    self.isLoaded = true
                } catch {
                    result.error = error
                    DispatchQueue.main.async { completion(result) }
                    return
                }
            }
            
            // Run prediction
            do {
                let mask = try self.wrapper.predict(inputImage)
                result.maskImage = mask
                result.success = true
            } catch {
                result.error = error
            }
            
            DispatchQueue.main.async { completion(result) }
        }
    }
}
