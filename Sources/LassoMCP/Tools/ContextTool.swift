import Foundation
import LassoCore
import MCP

// MARK: - Tool Definition

let contextTool = Tool(
    name: "lasso_context",
    description: "Get project context: scheme, workspace, simulator, bundle ID, Xcode version. Useful for understanding the current project setup.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
    ])
)

// MARK: - Handler

func handleContext(config: LassoConfig?) async throws -> CallTool.Result {
    var context: [String: String] = [:]

    if let config {
        if let s = config.scheme { context["scheme"] = s }
        if let w = config.workspace { context["workspace"] = w }
        if let p = config.project { context["project"] = p }
        if let sim = config.simulator { context["simulator"] = sim }
        if let bid = config.bundleId { context["bundle_id"] = bid }
    }

    if let device = try? await SimulatorManager.live.bootedDevice() {
        context["booted_simulator"] = device.name
        context["booted_udid"] = device.udid
        context["booted_runtime"] = device.runtime
    }

    if let xcode = try? await shell("xcodebuild -version | head -1") {
        context["xcode_version"] = xcode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(context)
    let json = String(data: data, encoding: .utf8) ?? "{}"
    return CallTool.Result(content: [.text(json)])
}
