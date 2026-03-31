import Foundation
import GrantivaCore
import MCP

/// UI automation tools: screenshot, tap, swipe, type, accessibility tree, accessibility check.
@available(macOS 15, *)
enum UITools {

    // MARK: - Tool Definitions

    static let definitions: [Tool] = [
        Tool(
            name: "grantiva_screenshot",
            description: "Take a screenshot of the iOS simulator. Returns a base64-encoded PNG image.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "format": .object([
                        "type": .string("string"),
                        "description": .string("Output format: 'base64' (default) or 'file'"),
                        "enum": .array([.string("base64"), .string("file")]),
                    ]),
                ]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_tap",
            description: "Tap on a UI element by accessibility label or by coordinates. After tapping, returns the updated accessibility tree so you can see what changed.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "label": .object([
                        "type": .string("string"),
                        "description": .string("Accessibility label of the element to tap"),
                    ]),
                    "x": .object([
                        "type": .string("number"),
                        "description": .string("X coordinate to tap (used if label is not provided)"),
                    ]),
                    "y": .object([
                        "type": .string("number"),
                        "description": .string("Y coordinate to tap (used if label is not provided)"),
                    ]),
                ]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_swipe",
            description: "Swipe on the iOS simulator screen. After swiping, returns the updated accessibility tree.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "direction": .object([
                        "type": .string("string"),
                        "description": .string("Swipe direction: up, down, left, right"),
                        "enum": .array([.string("up"), .string("down"), .string("left"), .string("right")]),
                    ]),
                ]),
                "required": .array([.string("direction")]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_type",
            description: "Type text into the currently focused field on the iOS simulator. After typing, returns the updated accessibility tree.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object([
                        "type": .string("string"),
                        "description": .string("Text to type"),
                    ]),
                ]),
                "required": .array([.string("text")]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_a11y_tree",
            description: "Get the current accessibility tree (view hierarchy) of the running app. Returns a JSON tree of all UI elements with their labels, types, frames, and states.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_a11y_check",
            description: "Run accessibility audit on the current screen. Checks for missing labels on interactive elements and tap targets smaller than 44pt.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),
    ]

    // MARK: - Handlers

    static func screenshot(
        wda: WDAClient,
        session: RunnerSessionInfo,
        arguments: [String: Value]
    ) async throws -> CallTool.Result {
        let format = arguments["format"]?.stringValue ?? "base64"

        let imageData: Data
        // Prefer simctl screenshot for full-device fidelity when UDID is available
        if !session.udid.isEmpty {
            let tmpPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("grantiva-mcp-\(UUID().uuidString).png").path
            defer { try? FileManager.default.removeItem(atPath: tmpPath) }
            _ = try await shell("xcrun simctl io \(session.udid) screenshot \"\(tmpPath)\"")
            imageData = try Data(contentsOf: URL(fileURLWithPath: tmpPath))
        } else {
            imageData = try await wda.screenshot()
        }

        if format == "file" {
            let outPath = ".grantiva/mcp-screenshot.png"
            try FileManager.default.createDirectory(atPath: ".grantiva", withIntermediateDirectories: true)
            try imageData.write(to: URL(fileURLWithPath: outPath))
            return CallTool.Result(
                content: [.text(text: "Screenshot saved to \(outPath)", annotations: nil, _meta: nil)]
            )
        }

        let base64 = imageData.base64EncodedString()
        return CallTool.Result(
            content: [.image(data: base64, mimeType: "image/png", annotations: nil, _meta: nil)]
        )
    }

    static func tap(wda: WDAClient, arguments: [String: Value]) async throws -> CallTool.Result {
        if let label = arguments["label"]?.stringValue {
            try await wda.tapByLabel(label)
            // Brief settle time for animations
            try await Task.sleep(nanoseconds: 500_000_000)
            let tree = try await fetchHierarchyJSON(wda: wda)
            return CallTool.Result(
                content: [
                    .text(text: "Tapped on \"\(label)\". Updated hierarchy:\n\(tree)", annotations: nil, _meta: nil),
                ]
            )
        } else if let x = arguments["x"]?.doubleValue, let y = arguments["y"]?.doubleValue {
            try await wda.tapByCoordinate(x, y)
            try await Task.sleep(nanoseconds: 500_000_000)
            let tree = try await fetchHierarchyJSON(wda: wda)
            return CallTool.Result(
                content: [
                    .text(text: "Tapped at (\(Int(x)), \(Int(y))). Updated hierarchy:\n\(tree)", annotations: nil, _meta: nil),
                ]
            )
        } else {
            return CallTool.Result(
                content: [.text(text: "Error: provide either 'label' or both 'x' and 'y' coordinates.", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    static func swipe(wda: WDAClient, arguments: [String: Value]) async throws -> CallTool.Result {
        guard let direction = arguments["direction"]?.stringValue else {
            return CallTool.Result(
                content: [.text(text: "Error: 'direction' is required.", annotations: nil, _meta: nil)],
                isError: true
            )
        }
        try await wda.swipe(direction)
        try await Task.sleep(nanoseconds: 500_000_000)
        let tree = try await fetchHierarchyJSON(wda: wda)
        return CallTool.Result(
            content: [
                .text(text: "Swiped \(direction). Updated hierarchy:\n\(tree)", annotations: nil, _meta: nil),
            ]
        )
    }

    static func type(wda: WDAClient, arguments: [String: Value]) async throws -> CallTool.Result {
        guard let text = arguments["text"]?.stringValue else {
            return CallTool.Result(
                content: [.text(text: "Error: 'text' is required.", annotations: nil, _meta: nil)],
                isError: true
            )
        }
        try await wda.typeText(text)
        try await Task.sleep(nanoseconds: 300_000_000)
        let tree = try await fetchHierarchyJSON(wda: wda)
        return CallTool.Result(
            content: [
                .text(text: "Typed \"\(text)\". Updated hierarchy:\n\(tree)", annotations: nil, _meta: nil),
            ]
        )
    }

    static func a11yTree(wda: WDAClient) async throws -> CallTool.Result {
        let tree = try await fetchHierarchyJSON(wda: wda)
        return CallTool.Result(
            content: [.text(text: tree, annotations: nil, _meta: nil)]
        )
    }

    static func a11yCheck(wda: WDAClient, config: GrantivaConfig?) async throws -> CallTool.Result {
        let hierarchy = try await wda.hierarchy()
        let rules = config?.a11y.rules ?? ["missing_label", "small_tap_target"]

        var violations: [[String: String]] = []
        checkViolations(element: hierarchy, rules: rules, violations: &violations)

        if violations.isEmpty {
            return CallTool.Result(
                content: [.text(text: "No accessibility violations found.", annotations: nil, _meta: nil)]
            )
        }

        let jsonData = try JSONSerialization.data(withJSONObject: violations, options: [.prettyPrinted, .sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        return CallTool.Result(
            content: [
                .text(
                    text: "Found \(violations.count) accessibility violation(s):\n\(jsonString)",
                    annotations: nil, _meta: nil
                ),
            ]
        )
    }

    // MARK: - Private Helpers

    private static func fetchHierarchyJSON(wda: WDAClient) async throws -> String {
        let tree = try await wda.hierarchy()
        let data = try JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Recursively check the hierarchy for accessibility violations.
    private static func checkViolations(
        element: [String: Any],
        rules: [String],
        violations: inout [[String: String]]
    ) {
        let type = element["type"] as? String ?? ""
        let label = element["label"] as? String ?? ""
        let name = element["name"] as? String ?? ""
        let enabled = element["enabled"] as? Bool ?? true

        // Interactive element types that need labels
        let interactiveTypes = [
            "XCUIElementTypeButton",
            "XCUIElementTypeTextField",
            "XCUIElementTypeSecureTextField",
            "XCUIElementTypeSwitch",
            "XCUIElementTypeSlider",
            "XCUIElementTypeStepper",
            "XCUIElementTypeLink",
            "XCUIElementTypeSegmentedControl",
        ]

        let isInteractive = interactiveTypes.contains(type)

        // Rule: missing_label
        if rules.contains("missing_label") && isInteractive && enabled {
            if label.isEmpty && name.isEmpty {
                violations.append([
                    "rule": "missing_label",
                    "type": type,
                    "message": "Interactive element of type \(type) has no accessibility label or name.",
                ])
            }
        }

        // Rule: small_tap_target
        if rules.contains("small_tap_target") && isInteractive && enabled {
            if let frame = element["frame"] as? [String: String],
               let wStr = frame["width"], let hStr = frame["height"],
               let w = Double(wStr), let h = Double(hStr) {
                if w < 44 || h < 44 {
                    let desc = label.isEmpty ? (name.isEmpty ? type : name) : label
                    violations.append([
                        "rule": "small_tap_target",
                        "type": type,
                        "element": desc,
                        "size": "\(Int(w))x\(Int(h))",
                        "message": "Tap target \"\(desc)\" is \(Int(w))x\(Int(h))pt, below the 44x44pt minimum.",
                    ])
                }
            }
        }

        // Recurse into children
        if let children = element["children"] as? [[String: Any]] {
            for child in children {
                checkViolations(element: child, rules: rules, violations: &violations)
            }
        }
    }
}

// MARK: - Value Helpers

extension Value {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d):
            return d
        case .int(let i):
            return Double(i)
        case .string(let s):
            return Double(s)
        default:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let i):
            return i
        case .double(let d):
            return Int(d)
        case .string(let s):
            return Int(s)
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var arrayValue: [Value]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    var objectValue: [String: Value]? {
        if case .object(let obj) = self { return obj }
        return nil
    }
}
