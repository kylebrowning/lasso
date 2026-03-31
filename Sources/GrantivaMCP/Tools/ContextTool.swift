import Foundation
import GrantivaCore
import MCP

/// Context tool: returns project configuration, booted simulator info, and Xcode version.
@available(macOS 15, *)
enum ContextTool {

    // MARK: - Tool Definition

    static let definition = Tool(
        name: "grantiva_context",
        description: "Get current project context: grantiva.yml config, booted simulator info, Xcode version, and runner session status.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
        annotations: .init(readOnlyHint: true, openWorldHint: false)
    )

    // MARK: - Handler

    static func context(
        config: GrantivaConfig?,
        simManager: SimulatorManager
    ) async throws -> CallTool.Result {
        var sections: [String] = []

        // Config
        if let config {
            var configLines = ["[Config]"]
            if let scheme = config.scheme { configLines.append("  scheme: \(scheme)") }
            if let workspace = config.workspace { configLines.append("  workspace: \(workspace)") }
            if let project = config.project { configLines.append("  project: \(project)") }
            if let simulator = config.simulator { configLines.append("  simulator: \(simulator)") }
            if let bundleId = config.bundleId { configLines.append("  bundle_id: \(bundleId)") }
            if let buildSettings = config.buildSettings, !buildSettings.isEmpty {
                configLines.append("  build_settings: \(buildSettings.joined(separator: " "))")
            }
            configLines.append("  screens: \(config.screens.count)")
            sections.append(configLines.joined(separator: "\n"))
        } else {
            sections.append("[Config]\n  No grantiva.yml found in current directory.")
        }

        // Booted simulator
        if let device = try? await simManager.bootedDevice() {
            sections.append("""
                [Simulator]
                  name: \(device.name)
                  udid: \(device.udid)
                  runtime: \(device.runtime)
                  state: \(device.state)
                """)
        } else {
            sections.append("[Simulator]\n  No simulator booted.")
        }

        // Xcode version
        let xcodeVersion = try? await shell("xcodebuild -version")
        if let version = xcodeVersion {
            sections.append("[Xcode]\n  \(version.replacingOccurrences(of: "\n", with: "\n  "))")
        }

        // Runner session
        if let session = try? RunnerSessionInfo.load(), session.isAlive {
            sections.append("""
                [Runner Session]
                  pid: \(session.pid)
                  wda_port: \(session.wdaPort)
                  bundle_id: \(session.bundleId)
                  udid: \(session.udid)
                """)
        } else {
            sections.append("[Runner Session]\n  No active session.")
        }

        return CallTool.Result(
            content: [.text(text: sections.joined(separator: "\n\n"), annotations: nil, _meta: nil)]
        )
    }
}
