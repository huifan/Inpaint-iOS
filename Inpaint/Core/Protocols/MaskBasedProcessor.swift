//
//  MaskBasedProcessor.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit

/// Extension protocol for processors requiring a user-drawn mask
protocol MaskBasedProcessor: ImageProcessor {
    func process(
        input: ProcessingInput,
        mask: UIImage,
        maskRects: [CGRect],
        options: ProcessingOptions,
        completion: @escaping (ProcessingResult) -> Void
    )
}
