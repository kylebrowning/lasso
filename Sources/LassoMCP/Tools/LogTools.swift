import Foundation
import LassoCore
import MCP

let logsTool = Tool(
    name: "lasso_logs",
    description: "Get recent log output from the booted iOS Simulator. Filter by subsystem, category, process, or log level.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "subsystem": .object([
                "type": .string("string"),
                "description": .string("Filter by subsystem (e.g. 'com.example.myapp')"),
            ]),
            "category": .object([
                "type": .string("string"),
                "description": .string("Filter by category"),
            ]),
            "process": .object([
                "type": .string("string"),
                "description": .string("Filter by process name"),
            ]),
            "level": .object([
                "type": .string("string"),
                "description": .string("Minimum log level: default, info, debug, error, fault"),
            ]),
            "last": .object([
                "type": .string("string"),
                "description": .string("Time duration for recent logs (e.g. '5m', '1h', '30s'). Defaults to '1m'."),
            ]),
        ]),
    ])
)

let logTools: [Tool] = [logsTool]

func handleLogs(arguments: [String: Value]?) async throws -> CallTool.Result {
    let udid = try await SimulatorManager.live.bootedUDID()
    let filter = LogFilter(
        subsystem: arguments?["subsystem"]?.stringValue,
        category: arguments?["category"]?.stringValue,
        process: arguments?["process"]?.stringValue,
        level: arguments?["level"]?.stringValue
    )
    let last = arguments?["last"]?.stringValue ?? "1m"

    let entries = try await SimulatorLog.live.fetchRecent(udid, filter, last)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(entries)
    let json = String(data: data, encoding: .utf8) ?? "[]"
    return CallTool.Result(content: [.text(json)])
}
