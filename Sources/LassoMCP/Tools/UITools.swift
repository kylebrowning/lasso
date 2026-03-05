import Foundation
import LassoCore
import MCP

// MARK: - Tool Definitions

let screenshotTool = Tool(
    name: "lasso_screenshot",
    description: "Capture a screenshot of the booted iOS Simulator. Returns a base64-encoded PNG image.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
    ])
)

let tapTool = Tool(
    name: "lasso_tap",
    description: "Tap an element on screen. Provide either a label (accessibility label, value, or identifier) OR x,y coordinates.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "label": .object([
                "type": .string("string"),
                "description": .string("Accessibility label, value, or identifier of the element to tap"),
            ]),
            "x": .object([
                "type": .string("number"),
                "description": .string("X coordinate to tap"),
            ]),
            "y": .object([
                "type": .string("number"),
                "description": .string("Y coordinate to tap"),
            ]),
        ]),
    ])
)

let swipeTool = Tool(
    name: "lasso_swipe",
    description: "Swipe/scroll in a direction on the booted simulator.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "direction": .object([
                "type": .string("string"),
                "description": .string("Swipe direction: up, down, left, or right"),
                "enum": .array([.string("up"), .string("down"), .string("left"), .string("right")]),
            ]),
        ]),
        "required": .array([.string("direction")]),
    ])
)

let typeTool = Tool(
    name: "lasso_type",
    description: "Type text into the currently focused field on the simulator.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "text": .object([
                "type": .string("string"),
                "description": .string("The text to type"),
            ]),
        ]),
        "required": .array([.string("text")]),
    ])
)

let a11yTreeTool = Tool(
    name: "lasso_a11y_tree",
    description: "Get the full accessibility hierarchy of the current screen as JSON. Returns element roles, labels, values, identifiers, frames, and children.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
    ])
)

let a11yCheckTool = Tool(
    name: "lasso_a11y_check",
    description: "Check the current screen for accessibility violations (missing labels, small tap targets). Returns only violations found.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
    ])
)

let uiTools: [Tool] = [screenshotTool, tapTool, swipeTool, typeTool, a11yTreeTool, a11yCheckTool]

// MARK: - Value Helpers

extension Value {
    var numericValue: Double? {
        if let d = doubleValue { return d }
        if let i = intValue { return Double(i) }
        return nil
    }
}

// MARK: - Handlers

func handleScreenshot(config: LassoConfig?, driverPort: UInt16) async throws -> CallTool.Result {
    let udid = try await SimulatorManager.live.bootedUDID()
    let ui = UIAutomation(udid: udid, driverClient: .live(port: driverPort))
    let data = try await ui.screenshot()
    let base64 = data.base64EncodedString()
    return CallTool.Result(content: [.image(data: base64, mimeType: "image/png", metadata: nil)])
}

func handleTap(arguments: [String: Value]?, config: LassoConfig?, driverPort: UInt16) async throws -> CallTool.Result {
    let udid = try await SimulatorManager.live.bootedUDID()
    let ui = UIAutomation(udid: udid, driverClient: .live(port: driverPort))

    if let label = arguments?["label"]?.stringValue {
        try await ui.tap(label: label)
        return CallTool.Result(content: [.text("Tapped element: \"\(label)\"")])
    } else if let x = arguments?["x"]?.numericValue, let y = arguments?["y"]?.numericValue {
        try await ui.tap(x: x, y: y)
        return CallTool.Result(content: [.text("Tapped at (\(x), \(y))")])
    } else {
        return CallTool.Result(content: [.text("Error: provide either 'label' or both 'x' and 'y'")], isError: true)
    }
}

func handleSwipe(arguments: [String: Value]?, config: LassoConfig?, driverPort: UInt16) async throws -> CallTool.Result {
    guard let dirStr = arguments?["direction"]?.stringValue,
          let direction = SwipeDirection(rawValue: dirStr) else {
        return CallTool.Result(content: [.text("Error: 'direction' must be one of: up, down, left, right")], isError: true)
    }
    let udid = try await SimulatorManager.live.bootedUDID()
    let ui = UIAutomation(udid: udid, driverClient: .live(port: driverPort))
    try await ui.swipe(direction: direction)
    return CallTool.Result(content: [.text("Swiped \(dirStr)")])
}

func handleType(arguments: [String: Value]?, config: LassoConfig?, driverPort: UInt16) async throws -> CallTool.Result {
    guard let text = arguments?["text"]?.stringValue else {
        return CallTool.Result(content: [.text("Error: 'text' parameter is required")], isError: true)
    }
    let udid = try await SimulatorManager.live.bootedUDID()
    let ui = UIAutomation(udid: udid, driverClient: .live(port: driverPort))
    try await ui.type(text)
    return CallTool.Result(content: [.text("Typed: \"\(text)\"")])
}

func handleA11yTree(config: LassoConfig?, driverPort: UInt16) async throws -> CallTool.Result {
    let udid = try await SimulatorManager.live.bootedUDID()
    let ui = UIAutomation(udid: udid, driverClient: .live(port: driverPort))
    let tree = try await ui.hierarchy()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(tree)
    let json = String(data: data, encoding: .utf8) ?? "{}"
    return CallTool.Result(content: [.text(json)])
}

func handleA11yCheck(config: LassoConfig?, driverPort: UInt16) async throws -> CallTool.Result {
    let udid = try await SimulatorManager.live.bootedUDID()
    let ui = UIAutomation(udid: udid, driverClient: .live(port: driverPort))
    let violations = try await ui.accessibilityViolations()
    if violations.isEmpty {
        return CallTool.Result(content: [.text("No accessibility violations found.")])
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(violations)
    let json = String(data: data, encoding: .utf8) ?? "[]"
    return CallTool.Result(content: [.text("Found \(violations.count) violation(s):\n\(json)")])
}
