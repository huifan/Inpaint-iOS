//
//  EnhancementMode.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import Foundation

enum EnhancementMode: String {
    case autoEnhance = "auto_enhance"
    case superResolution2x = "sr_2x"
    case superResolution4x = "sr_4x"
    case denoise = "denoise"

    static let `default`: EnhancementMode = .autoEnhance
}
