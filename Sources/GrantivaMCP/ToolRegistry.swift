import Foundation
import GrantivaCore
import MCP

/// Central registry that holds references to all dependencies and dispatches
/// tool calls and resource reads to the appropriate handler.
@available(macOS 15, *)
struct ToolRegistry: Sendable {
    let wda: WDAClient
    let config: GrantivaConfig?
    let session: RunnerSessionInfo
    let simulatorManager: SimulatorManager
    let buildRunner: XcodeBuildRunner

    // MARK: - Tool Definitions

    func allTools() -> [Tool] {
        UITools.definitions
            + BuildTools.definitions
            + SimTools.definitions
            + [ContextTool.definition]
            + ScriptTools.definitions
            + VRTTools.definitions
    }

    // MARK: - Resource Definitions

    func allResources() -> [Resource] {
        [
            Resource(
                name: "hierarchy",
                uri: "grantiva://hierarchy",
                description: "Current view hierarchy as JSON tree",
                mimeType: "application/json"
            ),
            Resource(
                name: "screenshot",
                uri: "grantiva://screenshot",
                description: "Current screenshot as base64 PNG",
                mimeType: "image/png"
            ),
        ]
    }

    // MARK: - Tool Dispatch

    func call(
        name: String,
        arguments: [String: Value],
        server: Server
    ) async throws -> CallTool.Result {
        let result: CallTool.Result

        switch name {
        // UI Tools
        case "grantiva_screenshot":
            result = try await UITools.screenshot(wda: wda, session: session, arguments: arguments)
        case "grantiva_tap":
            result = try await UITools.tap(wda: wda, arguments: arguments)
        case "grantiva_swipe":
            result = try await UITools.swipe(wda: wda, arguments: arguments)
        case "grantiva_type":
            result = try await UITools.type(wda: wda, arguments: arguments)
        case "grantiva_a11y_tree":
            result = try await UITools.a11yTree(wda: wda)
        case "grantiva_a11y_check":
            result = try await UITools.a11yCheck(wda: wda, config: config)

        // Build Tools
        case "grantiva_build":
            result = try await BuildTools.build(runner: buildRunner, config: config, simManager: simulatorManager, arguments: arguments)
        case "grantiva_run":
            result = try await BuildTools.run(runner: buildRunner, config: config, simManager: simulatorManager, arguments: arguments)
        case "grantiva_test":
            result = try await BuildTools.test(runner: buildRunner, config: config, simManager: simulatorManager, arguments: arguments)

        // Sim Tools
        case "grantiva_sim_list":
            result = try await SimTools.list(simManager: simulatorManager, arguments: arguments)
        case "grantiva_sim_boot":
            result = try await SimTools.boot(simManager: simulatorManager, arguments: arguments)

        // Context
        case "grantiva_context":
            result = try await ContextTool.context(config: config, simManager: simulatorManager)

        // Script
        case "grantiva_script":
            result = try await ScriptTools.script(wda: wda, arguments: arguments)

        // VRT Tools
        case "grantiva_vrt_capture":
            result = try await VRTTools.capture(arguments: arguments)
        case "grantiva_vrt_compare":
            result = try await VRTTools.compare(arguments: arguments)
        case "grantiva_vrt_approve":
            result = try await VRTTools.approve(arguments: arguments)

        default:
            return CallTool.Result(
                content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        // After UI-mutating actions, notify resource subscribers about hierarchy change
        let uiMutatingTools = ["grantiva_tap", "grantiva_swipe", "grantiva_type", "grantiva_script"]
        if uiMutatingTools.contains(name) {
            try? await notifyHierarchyUpdate(server: server)
        }

        return result
    }

    // MARK: - Resource Read

    func readResource(uri: String) async throws -> [Resource.Content] {
        switch uri {
        case "grantiva://hierarchy":
            let tree = try await wda.hierarchy()
            let jsonData = try JSONSerialization.data(
                withJSONObject: tree, options: [.prettyPrinted, .sortedKeys]
            )
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return [.text(jsonString, uri: uri, mimeType: "application/json")]

        case "grantiva://screenshot":
            let imageData = try await wda.screenshot()
            return [.binary(imageData, uri: uri, mimeType: "image/png")]

        default:
            throw MCPError.invalidRequest("Unknown resource URI: \(uri)")
        }
    }

    // MARK: - Notifications

    private func notifyHierarchyUpdate(server: Server) async throws {
        let notification = ResourceUpdatedNotification.message(
            .init(uri: "grantiva://hierarchy")
        )
        try await server.notify(notification)
    }
}
