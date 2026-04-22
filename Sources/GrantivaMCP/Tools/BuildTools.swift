import Foundation
import GrantivaCore
import MCP

/// Build, run, and test tools using XcodeBuildRunner.
@available(macOS 15, *)
enum BuildTools {

    // MARK: - Tool Definitions

    static let definitions: [Tool] = [
        Tool(
            name: "grantiva_build",
            description: "Build the iOS project using xcodebuild. Returns build result with success status, duration, warnings, and errors.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string("Xcode scheme to build (uses grantiva.yml if omitted)"),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string("Simulator name for destination (default: 'iPhone 16')"),
                    ]),
                ]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_run",
            description: "Build, install, and launch the app on the iOS simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string("Xcode scheme to build (uses grantiva.yml if omitted)"),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string("Simulator name (default: 'iPhone 16')"),
                    ]),
                ]),
            ]),
            annotations: .init(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        ),
        Tool(
            name: "grantiva_test",
            description: "Run the project's test suite using xcodebuild test. Returns pass/fail counts and output.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string("Xcode scheme to test (uses grantiva.yml if omitted)"),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string("Simulator name for destination (default: 'iPhone 16')"),
                    ]),
                ]),
            ]),
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),
    ]

    // MARK: - Handlers

    static func build(
        runner: XcodeBuildRunner,
        config: GrantivaConfig?,
        simManager: SimulatorManager,
        arguments: [String: Value]
    ) async throws -> CallTool.Result {
        let scheme = arguments["scheme"]?.stringValue ?? config?.scheme
        guard let scheme else {
            return CallTool.Result(
                content: [.text(text: "Error: no scheme specified. Pass 'scheme' or set it in grantiva.yml.", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        let simName = arguments["simulator"]?.stringValue ?? config?.simulator ?? "iPhone 16"
        let device = try await simManager.boot(nameOrUDID: simName)
        let destination = "platform=iOS Simulator,id=\(device.udid)"

        let result = try await runner.build(
            scheme: scheme,
            workspace: config?.workspace,
            project: config?.project,
            destination: destination,
            buildSettings: config?.buildSettings ?? []
        )

        let summary = """
            Build \(result.success ? "succeeded" : "FAILED")
            Scheme: \(result.scheme)
            Duration: \(String(format: "%.1fs", result.duration))
            Warnings: \(result.warnings.count)
            Errors: \(result.errors.count)\(result.errors.isEmpty ? "" : "\n" + result.errors.joined(separator: "\n"))
            """
        return CallTool.Result(
            content: [.text(text: summary, annotations: nil, _meta: nil)],
            isError: !result.success ? true : nil
        )
    }

    static func run(
        runner: XcodeBuildRunner,
        config: GrantivaConfig?,
        simManager: SimulatorManager,
        arguments: [String: Value]
    ) async throws -> CallTool.Result {
        let scheme = arguments["scheme"]?.stringValue ?? config?.scheme
        guard let scheme else {
            return CallTool.Result(
                content: [.text(text: "Error: no scheme specified. Pass 'scheme' or set it in grantiva.yml.", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        let bundleId = config?.bundleId
        guard let bundleId else {
            return CallTool.Result(
                content: [.text(text: "Error: no bundle_id in grantiva.yml. Cannot launch app.", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        let simName = arguments["simulator"]?.stringValue ?? config?.simulator ?? "iPhone 16"
        let device = try await simManager.boot(nameOrUDID: simName)
        let destination = "platform=iOS Simulator,id=\(device.udid)"

        let buildResult = try await runner.build(
            scheme: scheme,
            workspace: config?.workspace,
            project: config?.project,
            destination: destination,
            buildSettings: config?.buildSettings ?? []
        )

        guard buildResult.success else {
            let errors = buildResult.errors.joined(separator: "\n")
            return CallTool.Result(
                content: [.text(text: "Build failed:\n\(errors)", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        if let productPath = buildResult.productPath {
            try await runner.install(bundleId: bundleId, productPath: productPath, udid: device.udid)
        }
        try await runner.launch(bundleId: bundleId, udid: device.udid)

        return CallTool.Result(
            content: [
                .text(
                    text: "App built and launched.\nScheme: \(scheme)\nBundle ID: \(bundleId)\nSimulator: \(device.name)",
                    annotations: nil, _meta: nil
                ),
            ]
        )
    }

    static func test(
        runner: XcodeBuildRunner,
        config: GrantivaConfig?,
        simManager: SimulatorManager,
        arguments: [String: Value]
    ) async throws -> CallTool.Result {
        let scheme = arguments["scheme"]?.stringValue ?? config?.scheme
        guard let scheme else {
            return CallTool.Result(
                content: [.text(text: "Error: no scheme specified. Pass 'scheme' or set it in grantiva.yml.", annotations: nil, _meta: nil)],
                isError: true
            )
        }

        let simName = arguments["simulator"]?.stringValue ?? config?.simulator ?? "iPhone 16"
        let device = try await simManager.boot(nameOrUDID: simName)
        let destination = "platform=iOS Simulator,id=\(device.udid)"

        let result = try await runner.test(
            scheme: scheme,
            workspace: config?.workspace,
            project: config?.project,
            destination: destination
        )

        let summary = """
            Tests \(result.success ? "passed" : "FAILED")
            Scheme: \(result.scheme)
            Duration: \(String(format: "%.1fs", result.duration))
            Passed: \(result.testsPassed)
            Failed: \(result.testsFailed)
            """
        return CallTool.Result(
            content: [.text(text: summary, annotations: nil, _meta: nil)],
            isError: !result.success ? true : nil
        )
    }
}
