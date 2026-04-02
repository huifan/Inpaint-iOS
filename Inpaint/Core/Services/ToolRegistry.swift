//
//  ToolRegistry.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import Foundation

final class ToolRegistry {
    static let shared = ToolRegistry()

    private var processors: [String: any ImageProcessor] = [:]

    private init() {}

    func register(_ processor: any ImageProcessor) {
        processors[processor.identifier] = processor
        DispatchQueue.global(qos: .utility).async {
            processor.preload()
        }
    }

    func processor(for identifier: String) -> (any ImageProcessor)? {
        processors[identifier]
    }

    var allTools: [ToolDefinition] {
        processors.values.map(\.toolDefinition)
    }

    func tools(in group: ModuleGroup) -> [ToolDefinition] {
        allTools.filter { $0.moduleGroup == group }
    }

    /// Returns tools grouped by module, in display order
    func groupedTools() -> [(group: ModuleGroup, tools: [ToolDefinition])] {
        ModuleGroup.allCases.compactMap { group in
            let groupTools = tools(in: group)
            guard !groupTools.isEmpty else { return nil }
            return (group: group, tools: groupTools)
        }
    }
}
