import Foundation
import LassoCore
import MCP

let scriptTool = Tool(
    name: "lasso_script",
    description: """
        Run a sequence of UI actions in one call. Much faster than calling individual tools. \
        Each step is an object with an "action" key and action-specific parameters. \
        Actions: tap (label or x/y), swipe (direction: up/down/left/right), type (text), \
        wait (seconds, default 1), screenshot (optional name), back. \
        Example: [{"action":"tap","label":"Settings"},{"action":"wait","seconds":1},{"action":"tap","label":"Account"}]
        """,
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "steps": .object([
                "type": .string("array"),
                "description": .string("Array of step objects. Each has 'action' plus params."),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("tap"), .string("swipe"), .string("type"),
                                .string("wait"), .string("screenshot"), .string("back"),
                            ]),
                        ]),
                        "label": .object(["type": .string("string")]),
                        "x": .object(["type": .string("number")]),
                        "y": .object(["type": .string("number")]),
                        "direction": .object(["type": .string("string")]),
                        "text": .object(["type": .string("string")]),
                        "seconds": .object(["type": .string("number")]),
                        "name": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("action")]),
                ]),
            ]),
        ]),
        "required": .array([.string("steps")]),
    ])
)

let scriptTools: [Tool] = [scriptTool]

func handleScript(arguments: [String: Value]?, driverPort: UInt16) async throws -> CallTool.Result {
    guard let stepsValue = arguments?["steps"]?.arrayValue else {
        return CallTool.Result(content: [.text("Error: 'steps' array is required")], isError: true)
    }

    // Parse steps from MCP Value array
    var steps: [ScriptStep] = []
    for (i, stepValue) in stepsValue.enumerated() {
        guard let obj = stepValue.objectValue,
              let action = obj["action"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: step \(i + 1) missing 'action'")], isError: true
            )
        }

        switch action {
        case "tap":
            if let label = obj["label"]?.stringValue {
                steps.append(.tap(label: label))
            } else if let x = obj["x"]?.numericValue, let y = obj["y"]?.numericValue {
                steps.append(.tapCoordinate(x: x, y: y))
            } else {
                return CallTool.Result(
                    content: [.text("Error: step \(i + 1) tap needs 'label' or 'x'+'y'")], isError: true
                )
            }
        case "swipe":
            guard let dir = obj["direction"]?.stringValue else {
                return CallTool.Result(
                    content: [.text("Error: step \(i + 1) swipe needs 'direction'")], isError: true
                )
            }
            steps.append(.swipe(direction: dir))
        case "type":
            guard let text = obj["text"]?.stringValue else {
                return CallTool.Result(
                    content: [.text("Error: step \(i + 1) type needs 'text'")], isError: true
                )
            }
            steps.append(.type(text: text))
        case "wait":
            let seconds = obj["seconds"]?.numericValue ?? 1.0
            steps.append(.wait(seconds: seconds))
        case "screenshot":
            steps.append(.screenshot(name: obj["name"]?.stringValue))
        case "back":
            steps.append(.back)
        default:
            return CallTool.Result(
                content: [.text("Error: step \(i + 1) unknown action '\(action)'")], isError: true
            )
        }
    }

    let udid = try await SimulatorManager.live.bootedUDID()
    let ui = UIAutomation(udid: udid, driverClient: .live(port: driverPort))

    let result = try await ScriptRunner().run(
        steps: steps,
        ui: ui
    )

    let summary = result.steps.map { step in
        step.status == "ok" ? "  \u{2713} \(step.step)" : "  \u{2717} \(step.step): \(step.error ?? "unknown")"
    }.joined(separator: "\n")

    let ok = result.steps.filter { $0.status == "ok" }.count
    let text = "Ran \(ok)/\(result.steps.count) steps in \(String(format: "%.1f", result.duration))s\n\(summary)"
    return CallTool.Result(content: [.text(text)])
}
