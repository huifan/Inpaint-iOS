//
//  FilterDefinition.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit
import CoreImage

struct FilterDefinition {
    let identifier: String
    let nameKey: String
    let filters: [(name: String, parameters: [String: Any])]
    let defaultIntensity: Float

    static let allFilters: [FilterDefinition] = [
        FilterDefinition(
            identifier: "original",
            nameKey: "filter_original",
            filters: [],
            defaultIntensity: 1.0
        ),
        FilterDefinition(
            identifier: "bw_classic",
            nameKey: "filter_bw_classic",
            filters: [
                ("CIPhotoEffectMono", [:])
            ],
            defaultIntensity: 1.0
        ),
        FilterDefinition(
            identifier: "bw_noir",
            nameKey: "filter_bw_noir",
            filters: [
                ("CIPhotoEffectNoir", [:])
            ],
            defaultIntensity: 1.0
        ),
        FilterDefinition(
            identifier: "vintage",
            nameKey: "filter_vintage",
            filters: [
                ("CIPhotoEffectInstant", [:]),
                ("CISepiaTone", ["inputIntensity": 0.3])
            ],
            defaultIntensity: 1.0
        ),
        FilterDefinition(
            identifier: "warm",
            nameKey: "filter_warm",
            filters: [
                ("CITemperatureAndTint", ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5000, y: 0)])
            ],
            defaultIntensity: 1.0
        ),
        FilterDefinition(
            identifier: "cool",
            nameKey: "filter_cool",
            filters: [
                ("CITemperatureAndTint", ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 8000, y: 0)])
            ],
            defaultIntensity: 1.0
        ),
        FilterDefinition(
            identifier: "vivid",
            nameKey: "filter_vivid",
            filters: [
                ("CIVibrance", ["inputAmount": 0.5]),
                ("CIColorControls", ["inputSaturation": 1.3])
            ],
            defaultIntensity: 1.0
        ),
        FilterDefinition(
            identifier: "fade",
            nameKey: "filter_fade",
            filters: [
                ("CIPhotoEffectFade", [:])
            ],
            defaultIntensity: 1.0
        ),
        FilterDefinition(
            identifier: "chrome",
            nameKey: "filter_chrome",
            filters: [
                ("CIPhotoEffectChrome", [:])
            ],
            defaultIntensity: 1.0
        )
    ]
}
