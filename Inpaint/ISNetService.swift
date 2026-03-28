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
//    3. Extract → ONNXRuntime.xcframework
//    4. Drag ONNXRuntime.xcframework into Xcode project
//       • Copy items if needed ✓
//       • Destination: Inpaint target ✓
//    5. Build Phases → Link Binary With Libraries:
//       Add: libc++abi.tbd, Accelerate.framework, CoreML.framework
//
//  Option B: CocoaPods (onnxruntime-c)
//    1. Podfile already has: pod 'onnxruntime-c', '~> 1.24'
//    2. Run: pod install
//    3. Build Phases → Link Binary With Libraries:
//       Add: libc++abi.tbd, Accelerate.framework, CoreML.framework
//
//  Step 2: Add Model File
//  ----------------------
//  1. Download model from rembg cache (already on this machine):
//     cp ~/.u2net/isnet-general-use.onnx ~/Inpaint-iOS/Inpaint/
//  2. Drag Inpaint/isnet-general-use.onnx into Xcode
//     • Copy items if needed ✓
//     • Destination: Inpaint target ✓
//     • File inspector: Target Membership = Inpaint ✓
//
//  Step 3: Create Bridging Header (if not exists)
//  ------------------------------------------------
//  In Xcode: File → New → File → Header (Objective-C)
//  Named: Inpaint-Bridging-Header.h
//  Add to it:
//    #import "ISNetWrapper.h"
//
//  Step 4: Configure Xcode Project
//  --------------------------------
//  1. Build Settings:
//     - SWIFT_OBJC_BRIDGING_HEADER = Inpaint/Inpaint-Bridging-Header.h
//     - CLANG_CXX_LANGUAGE_STANDARD = c++17
//     - OTHER_LDFLAGS = -force_load (for ONNX Runtime dlsym approach)
//  2. Build Phases:
//     - Compile Sources: Add ISNetWrapper.mm
//     - Link Binary: Add ONNXRuntime.xcframework (or libonnxruntime from pod)
//
//  Step 5: Build & Run
//  -------------------
//  If build succeeds → auto-segmentation is ready!
//  If build fails → check console for error details
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
        var error: NSError?
        let success = wrapper.loadModel("isnet-general-use", error: &error)
        if success {
            isLoaded = true
            print("[ISNet] Model loaded successfully")
        } else {
            print("[ISNet] Model load failed: \(error?.localizedDescription ?? "unknown")")
        }
    }
    
    /// Synchronous mask prediction.
    /// Returns: grayscale mask (white=subject, black=background), or nil on failure.
    func predict(inputImage: UIImage) -> UIImage? {
        if !isLoaded {
            var error: NSError?
            let success = wrapper.loadModel("isnet-general-use", error: &error)
            if !success {
                print("[ISNet] Model not available: \(error?.localizedDescription ?? "")")
                return nil
            }
            isLoaded = true
        }
        
        var error: NSError?
        let mask = wrapper.predict(inputImage, error: &error)
        if mask == nil {
            print("[ISNet] Prediction failed: \(error?.localizedDescription ?? "unknown")")
        }
        return mask
    }
    
    /// Async mask prediction (background thread, result on main queue).
    func predictAsync(inputImage: UIImage, completion: @escaping (ISNetPredictionResult) -> Void) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            
            var result = ISNetPredictionResult()
            
            if !self.isLoaded {
                var error: NSError?
                let ok = self.wrapper.loadModel("isnet-general-use", error: &error)
                if !ok {
                    result.error = error ?? NSError(
                        domain: "ISNetService",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load model"]
                    )
                    DispatchQueue.main.async { completion(result) }
                    return
                }
                self.isLoaded = true
            }
            
            var error: NSError?
            let mask = self.wrapper.predict(inputImage, error: &error)
            if let mask = mask {
                result.maskImage = mask
                result.success = true
            } else {
                result.error = error ?? NSError(
                    domain: "ISNetService",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Prediction returned nil"]
                )
            }
            
            DispatchQueue.main.async { completion(result) }
        }
    }
}
