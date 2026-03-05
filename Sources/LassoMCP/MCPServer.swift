import Foundation
import LassoCore
import MCP

public struct MCPServer: Sendable {
    public let driverPort: UInt16

    public init(driverPort: UInt16 = 22088) {
        self.driverPort = driverPort
    }

    public func run() async throws {
        let config = try? LassoConfig.load()
        let driverPort = self.driverPort

        let allTools = uiTools + buildTools + simTools + [contextTool]

        let server = Server(
            name: "lasso",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: allTools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                switch params.name {
                // UI Tools
                case "lasso_screenshot":
                    return try await handleScreenshot(config: config, driverPort: driverPort)
                case "lasso_tap":
                    return try await handleTap(arguments: params.arguments, config: config, driverPort: driverPort)
                case "lasso_swipe":
                    return try await handleSwipe(arguments: params.arguments, config: config, driverPort: driverPort)
                case "lasso_type":
                    return try await handleType(arguments: params.arguments, config: config, driverPort: driverPort)
                case "lasso_a11y_tree":
                    return try await handleA11yTree(config: config, driverPort: driverPort)
                case "lasso_a11y_check":
                    return try await handleA11yCheck(config: config, driverPort: driverPort)

                // Build Tools
                case "lasso_build":
                    return try await handleBuild(arguments: params.arguments, config: config)
                case "lasso_run":
                    return try await handleRun(arguments: params.arguments, config: config)
                case "lasso_test":
                    return try await handleTest(arguments: params.arguments, config: config)

                // Sim Tools
                case "lasso_sim_list":
                    return try await handleSimList()
                case "lasso_sim_boot":
                    return try await handleSimBoot(arguments: params.arguments)

                // Context
                case "lasso_context":
                    return try await handleContext(config: config)

                default:
                    return CallTool.Result(content: [.text("Unknown tool: \(params.name)")], isError: true)
                }
            } catch let error as LassoError {
                return CallTool.Result(
                    content: [.text(error.localizedDescription)],
                    isError: true
                )
            } catch {
                return CallTool.Result(
                    content: [.text("Error: \(error.localizedDescription)")],
                    isError: true
                )
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
