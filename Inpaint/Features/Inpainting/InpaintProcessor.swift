//
//  InpaintProcessor.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit

final class InpaintProcessor: MaskBasedProcessor {

    let identifier = "inpainting"

    let toolDefinition = ToolDefinition(
        identifier: "inpainting",
        nameKey: "tool_inpainting",
        iconName: "eraser.fill",
        tier: .free,
        moduleGroup: .removalRepair
    )

    private var lama: LaMaImageInpenting { LaMaImageInpenting.shared }

    var isReady: Bool { lama.lama != nil }

    func preload() {
        // Triggers shared instance creation (and model load) on the calling queue.
        _ = LaMaImageInpenting.shared
    }

    func unload() {}

    // Single-image processing (not used for inpainting, but required by protocol)
    func process(input: ProcessingInput, options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        completion(.failure(NSError(domain: "InpaintProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mask required"])))
    }

    // Mask-based processing
    func process(input: ProcessingInput, mask: UIImage, maskRects: [CGRect], options: ProcessingOptions, completion: @escaping (ProcessingResult) -> Void) {
        lama.inpent(image: input.image, mask: mask, inpaintingRects: maskRects) { outImage, error in
            if let outImage = outImage {
                completion(.success(outImage))
            } else if let error = error {
                completion(.failure(error))
            } else {
                completion(.failure(NSError(domain: "InpaintProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
            }
        }
    }
}
