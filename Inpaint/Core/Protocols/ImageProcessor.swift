//
//  ImageProcessor.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit

/// Processing input containing the image and optional metadata
struct ProcessingInput {
    let image: UIImage
    let metadata: [String: Any]

    init(image: UIImage, metadata: [String: Any] = [:]) {
        self.image = image
        self.metadata = metadata
    }
}

/// Universal protocol for all image processing features
protocol ImageProcessor: AnyObject {
    /// Unique identifier for this processor
    var identifier: String { get }

    /// Human-readable tool definition (name, icon, tier)
    var toolDefinition: ToolDefinition { get }

    /// Whether the model is loaded and ready
    var isReady: Bool { get }

    /// Load the ML model into memory
    func preload()

    /// Release the ML model from memory
    func unload()

    /// Process an image with the given options
    func process(
        input: ProcessingInput,
        options: ProcessingOptions,
        completion: @escaping (ProcessingResult) -> Void
    )
}
