//
//  BackgroundMode.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit

/// Background replacement mode for the background removal feature
enum BackgroundMode: Equatable {
    case transparent
    case solidColor(UIColor)
    case blurred(radius: CGFloat)
    case customImage(UIImage)

    static let `default`: BackgroundMode = .transparent
}
