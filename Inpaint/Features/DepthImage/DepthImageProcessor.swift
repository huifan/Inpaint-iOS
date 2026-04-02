//
//  DepthImageProcessor.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit

/// Processor wrapper for 3D photo generation (navigation placeholder)
/// The actual processing happens inside DeepImageViewController/DepthImageSenceViewController
final class DepthImageProcessor: ImageProcessor {

    let identifier = "depth_image"

    let toolDefinition = ToolDefinition(
        identifier: "depth_image",
        nameKey: "tool_3d_photo",
        iconName: "cube.fill",
        tier: .pro,
        moduleGroup: .effectsCreative
    )

    var isReady: Bool { true }

    func preload() {}
    func unload() {}

    func process(input: ProcessingInput, options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        // 3D photo processing is handled by its own VC chain
        completion(.failure(NSError(domain: "DepthImageProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Use DeepImageViewController directly"])))
    }
}
