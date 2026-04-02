//
//  ProcessingResult.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit

struct ProcessingResult {
    let outputImage: UIImage?
    let error: Error?
    let metadata: [String: Any]

    var isSuccess: Bool { outputImage != nil && error == nil }

    static func success(_ image: UIImage, metadata: [String: Any] = [:]) -> ProcessingResult {
        ProcessingResult(outputImage: image, error: nil, metadata: metadata)
    }

    static func failure(_ error: Error) -> ProcessingResult {
        ProcessingResult(outputImage: nil, error: error, metadata: [:])
    }
}
