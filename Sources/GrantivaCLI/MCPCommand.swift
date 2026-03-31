import ArgumentParser
import GrantivaMCP

@available(macOS 15, *)
struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start the Grantiva MCP server for AI agent integration."
    )

    func run() async throws {
        try await GrantivaMCPServer().run()
    }
}
