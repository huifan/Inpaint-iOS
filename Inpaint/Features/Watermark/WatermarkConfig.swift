//
//  WatermarkConfig.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit

struct WatermarkConfig {
    enum WatermarkType {
        case text(String, UIFont, UIColor)
        case image(UIImage)
    }

    let type: WatermarkType
    var position: CGPoint
    var scale: CGFloat
    var rotation: CGFloat
    var opacity: CGFloat
    var isTiled: Bool

    static func defaultText() -> WatermarkConfig {
        WatermarkConfig(
            type: .text("Watermark", .systemFont(ofSize: 36, weight: .bold), .white),
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.0,
            rotation: 0,
            opacity: 0.5,
            isTiled: false
        )
    }
}
