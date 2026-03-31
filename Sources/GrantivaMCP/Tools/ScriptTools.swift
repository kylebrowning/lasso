import Foundation
import GrantivaCore
import MCP

/// Script tool: execute a batch of UI actions sequentially.
@available(macOS 15, *)
enum ScriptTools {

    // MARK: - Tool Definition

    static let definitions: [Tool] = [
        Tool(
            name: "grantiva_script",
            description: """
                Execute a batch of UI actions sequentially. Each step is an object with one action key. \
                Supported actions: tap (by label), tap_xy (by coordinates), swipe (direction), type (text), wait (seconds). \
                Returns the final accessibility tree after all steps complete.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "steps": .object([
                        "type": .string("array"),
                        "description": .string("Array of step objects. Each has one key: tap, tap_xy, swipe, type, or wait."),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "tap": .object([
                                    "type": .string("string"),
                                    "description": .string("Accessibility label to tap"),
                                ]),
                                "tap_xy": .object([
                                    "type": .string("object"),
                                    "description": .string("Coordinates to tap: {x, y}"),
                                    "properties": .object([
                                        "x": .object(["type": .string("number")]),
                                        "y": .object(["type": .string("number")]),
                                    ]),
                                ]),
                                "swipe": .object([
                                    "type": .string("string"),
                                    "description": .string("Swipe direction: up, down, left, right"),
                                ]),
                                "type": .object([
                                    "type": .string("string"),
                                    "description": .string("Text to type into focused field"),
                                ]),
                                "wait": .object([
                                    "type": .string("number"),
                                    "description": .string("Seconds to wait"),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
                "required": .array([.string("steps")]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        ),
    ]

    // MARK: - Handler

    static func script(wda: WDAClient, arguments: [String: Value]) async throws -> CallTool.Result {
        guard let stepsValue = arguments["steps"]?.arrayValue else {
            return CallTool.Result(
                content: [.text(text: "Error: 'steps' array is required.", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        var log: [String] = []

        for (index, stepValue) in stepsValue.enumerated() {
            guard let step = stepValue.objectValue else {
                log.append("Step \(index + 1): skipped (not an object)")
                continue
            }

            let stepNum = index + 1

            if let label = step["tap"]?.stringValue {
                try await wda.tapByLabel(label)
                try await Task.sleep(nanoseconds: 500_000_000)
                log.append("Step \(stepNum): tapped \"\(label)\"")
            } else if let tapXY = step["tap_xy"]?.objectValue,
                      let x = tapXY["x"]?.doubleValue,
                      let y = tapXY["y"]?.doubleValue {
                try await wda.tapByCoordinate(x, y)
                try await Task.sleep(nanoseconds: 500_000_000)
                log.append("Step \(stepNum): tapped at (\(Int(x)), \(Int(y)))")
            } else if let direction = step["swipe"]?.stringValue {
                try await wda.swipe(direction)
                try await Task.sleep(nanoseconds: 500_000_000)
                log.append("Step \(stepNum): swiped \(direction)")
            } else if let text = step["type"]?.stringValue {
                try await wda.typeText(text)
                try await Task.sleep(nanoseconds: 300_000_000)
                log.append("Step \(stepNum): typed \"\(text)\"")
            } else if let seconds = step["wait"]?.doubleValue {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                log.append("Step \(stepNum): waited \(seconds)s")
            } else {
                log.append("Step \(stepNum): unknown action, skipped")
            }
        }

        // Fetch final hierarchy
        let tree = try await wda.hierarchy()
        let jsonData = try JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted, .sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        let output = log.joined(separator: "\n") + "\n\nFinal hierarchy:\n" + jsonString
        return CallTool.Result(
            content: [.text(text: output, annotations: nil, _meta: nil)]
        )
    }
}
