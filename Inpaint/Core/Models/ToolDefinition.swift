//
//  ToolDefinition.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit

enum FeatureTier: String {
    case free
    case pro
}

enum ModuleGroup: String, CaseIterable {
    case removalRepair = "removal_repair"
    case enhancement = "enhancement"
    case effectsCreative = "effects_creative"
    case composition = "composition"

    var displayName: String {
        switch self {
        case .removalRepair: return *"module_removal_repair"
        case .enhancement: return *"module_enhancement"
        case .effectsCreative: return *"module_effects_creative"
        case .composition: return *"module_composition"
        }
    }
}

struct ToolDefinition {
    let identifier: String
    let nameKey: String
    let iconName: String
    let tier: FeatureTier
    let moduleGroup: ModuleGroup

    var displayName: String { *nameKey }
}
