import ArgumentParser
import LassoMCP

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start MCP stdio server for AI agent integration."
    )

    @Option(name: .long, help: "Driver server port (default: 22088)")
    var driverPort: UInt16 = 22088

    func run() async throws {
        try await MCPServer(driverPort: driverPort).run()
    }
}
