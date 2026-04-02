//
//  ProcessingOptions.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import Foundation

struct ProcessingOptions {
    let parameters: [String: Any]
    var watermarkConfig: WatermarkConfig?

    init(_ parameters: [String: Any] = [:]) {
        self.parameters = parameters
    }

    init(watermarkConfig: WatermarkConfig) {
        self.parameters = [:]
        self.watermarkConfig = watermarkConfig
    }

    func value<T>(for key: String) -> T? {
        parameters[key] as? T
    }
}
