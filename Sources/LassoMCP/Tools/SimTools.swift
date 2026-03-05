import Foundation
import LassoCore
import MCP

// MARK: - Tool Definitions

let simListTool = Tool(
    name: "lasso_sim_list",
    description: "List available iOS Simulators with name, UDID, state, runtime, and availability.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
    ])
)

let simBootTool = Tool(
    name: "lasso_sim_boot",
    description: "Boot an iOS Simulator by name or UDID.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "name_or_udid": .object([
                "type": .string("string"),
                "description": .string("Simulator name (e.g. 'iPhone 16') or UDID"),
            ]),
        ]),
        "required": .array([.string("name_or_udid")]),
    ])
)

let simTools: [Tool] = [simListTool, simBootTool]

// MARK: - Handlers

func handleSimList() async throws -> CallTool.Result {
    let devices = try await SimulatorManager().listDevices()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(devices)
    let json = String(data: data, encoding: .utf8) ?? "[]"
    return CallTool.Result(content: [.text(json)])
}

func handleSimBoot(arguments: [String: Value]?) async throws -> CallTool.Result {
    guard let nameOrUDID = arguments?["name_or_udid"]?.stringValue else {
        return CallTool.Result(content: [.text("Error: 'name_or_udid' is required")], isError: true)
    }
    let device = try await SimulatorManager().boot(nameOrUDID: nameOrUDID)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(device)
    let json = String(data: data, encoding: .utf8) ?? "{}"
    return CallTool.Result(content: [.text("Booted simulator:\n\(json)")])
}
