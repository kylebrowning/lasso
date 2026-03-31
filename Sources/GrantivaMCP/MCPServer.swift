import Foundation
import GrantivaCore
import MCP

/// The Grantiva MCP server. Exposes iOS simulator automation tools and resources
/// over the Model Context Protocol via stdio transport.
@available(macOS 15, *)
public struct GrantivaMCPServer: Sendable {
    public init() {}

    public func run() async throws {
        // Load config (optional - some tools work without it)
        let config = try? GrantivaConfig.load()

        // Resolve WDA session - start runner if not running
        let session: RunnerSessionInfo
        if let existing = try? RunnerSessionInfo.load(), existing.isAlive {
            session = existing
        } else {
            // No active session. The MCP server requires a running runner.
            // Tools that don't need WDA (build, sim, context) will still work,
            // but UI tools will fail gracefully.
            let port: UInt16 = 8100
            session = RunnerSessionInfo(
                pid: 0, wdaPort: port, bundleId: config?.bundleId ?? "",
                udid: "", startedAt: Date()
            )
        }

        let wda = WDAClient.live(port: session.wdaPort)
        let simManager = SimulatorManager.live
        let buildRunner = XcodeBuildRunner()

        // Build the tool registry
        let tools = ToolRegistry(
            wda: wda,
            config: config,
            session: session,
            simulatorManager: simManager,
            buildRunner: buildRunner
        )

        let allTools = tools.allTools()
        let allResources = tools.allResources()

        // Create and configure MCP server
        let server = Server(
            name: "grantiva",
            version: grantivaVersion,
            instructions: """
                Grantiva MCP server for iOS simulator automation. \
                Use grantiva_* tools to interact with the iOS simulator: \
                tap, swipe, type, take screenshots, inspect the accessibility tree, \
                build and run apps, manage simulators, and run visual regression tests.
                """,
            capabilities: .init(
                resources: .init(subscribe: true, listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: allTools)
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            let result = try await tools.call(
                name: params.name,
                arguments: params.arguments ?? [:],
                server: server
            )
            return result
        }

        // Register resources/list handler
        await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: allResources)
        }

        // Register resources/read handler
        await server.withMethodHandler(ReadResource.self) { params in
            let contents = try await tools.readResource(uri: params.uri)
            return ReadResource.Result(contents: contents)
        }

        // Register resources/subscribe handler
        await server.withMethodHandler(ResourceSubscribe.self) { params in
            // Subscription tracking is handled by the MCP server actor internally.
            // We just acknowledge it here.
            return Empty()
        }

        // Register resources/unsubscribe handler
        await server.withMethodHandler(ResourceUnsubscribe.self) { params in
            return Empty()
        }

        // Start on stdio transport
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
