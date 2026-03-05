import Foundation
import LassoCore
import MCP

// MARK: - Tool Definitions

let buildTool = Tool(
    name: "lasso_build",
    description: "Build the Xcode project. Returns build result with success status, duration, warnings, and errors.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "scheme": .object([
                "type": .string("string"),
                "description": .string("Xcode scheme to build. Defaults to lasso.yml scheme."),
            ]),
            "workspace": .object([
                "type": .string("string"),
                "description": .string("Xcode workspace path"),
            ]),
            "project": .object([
                "type": .string("string"),
                "description": .string("Xcode project path"),
            ]),
            "simulator": .object([
                "type": .string("string"),
                "description": .string("Simulator name for destination (default: iPhone 16)"),
            ]),
        ]),
    ])
)

let runTool = Tool(
    name: "lasso_run",
    description: "Build, install, and launch the app on a booted simulator.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "scheme": .object([
                "type": .string("string"),
                "description": .string("Xcode scheme to build. Defaults to lasso.yml scheme."),
            ]),
            "simulator": .object([
                "type": .string("string"),
                "description": .string("Simulator name (default: iPhone 16)"),
            ]),
            "bundle_id": .object([
                "type": .string("string"),
                "description": .string("App bundle identifier. Defaults to lasso.yml bundle_id."),
            ]),
            "skip_build": .object([
                "type": .string("boolean"),
                "description": .string("Skip building — use existing build artifacts from DerivedData."),
            ]),
            "app_path": .object([
                "type": .string("string"),
                "description": .string("Path to a pre-built .app bundle. Implies skip_build."),
            ]),
        ]),
    ])
)

let testTool = Tool(
    name: "lasso_test",
    description: "Run tests for the Xcode project. Returns test results with pass/fail counts.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "scheme": .object([
                "type": .string("string"),
                "description": .string("Xcode scheme to test. Defaults to lasso.yml scheme."),
            ]),
            "workspace": .object([
                "type": .string("string"),
                "description": .string("Xcode workspace path"),
            ]),
            "project": .object([
                "type": .string("string"),
                "description": .string("Xcode project path"),
            ]),
        ]),
    ])
)

let buildTools: [Tool] = [buildTool, runTool, testTool]

// MARK: - Handlers

func handleBuild(arguments: [String: Value]?, config: LassoConfig?) async throws -> CallTool.Result {
    let scheme = arguments?["scheme"]?.stringValue ?? config?.scheme
    guard let scheme else {
        return CallTool.Result(content: [.text("Error: 'scheme' is required (provide it or set it in lasso.yml)")], isError: true)
    }

    let workspace = arguments?["workspace"]?.stringValue ?? config?.workspace
    let project = arguments?["project"]?.stringValue ?? config?.project
    let simName = arguments?["simulator"]?.stringValue ?? config?.simulator ?? "iPhone 16"
    let destination = "platform=iOS Simulator,name=\(simName)"

    let result = try await XcodeBuildRunner().build(
        scheme: scheme, workspace: workspace, project: project, destination: destination
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    let json = String(data: data, encoding: .utf8) ?? "{}"
    return CallTool.Result(content: [.text(json)], isError: !result.success)
}

func handleRun(arguments: [String: Value]?, config: LassoConfig?) async throws -> CallTool.Result {
    let scheme = arguments?["scheme"]?.stringValue ?? config?.scheme
    guard let scheme else {
        return CallTool.Result(content: [.text("Error: 'scheme' is required (provide it or set it in lasso.yml)")], isError: true)
    }

    let simName = arguments?["simulator"]?.stringValue ?? config?.simulator ?? "iPhone 16"
    let bundleId = arguments?["bundle_id"]?.stringValue ?? config?.bundleId
    guard let bundleId else {
        return CallTool.Result(content: [.text("Error: 'bundle_id' is required (provide it or set it in lasso.yml)")], isError: true)
    }

    let workspace = config?.workspace
    let project = config?.project
    let destination = "platform=iOS Simulator,name=\(simName)"
    let skipBuild = arguments?["skip_build"]?.boolValue ?? false
    let appPath = arguments?["app_path"]?.stringValue

    let runner = XcodeBuildRunner()
    var productPath: String?
    var buildDuration: TimeInterval = 0

    if let appPath {
        let abs = (appPath as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: abs) else {
            return CallTool.Result(content: [.text("Error: App not found at \"\(abs)\"")], isError: true)
        }
        productPath = abs
    } else if skipBuild {
        let path = try await runner.resolveProductPath(
            scheme: scheme, workspace: workspace, project: project, destination: destination
        )
        guard FileManager.default.fileExists(atPath: path) else {
            return CallTool.Result(content: [.text("Error: Build artifacts not found at \"\(path)\". Run a build first.")], isError: true)
        }
        productPath = path
    } else {
        // Build
        let buildResult = try await runner.build(
            scheme: scheme, workspace: workspace, project: project, destination: destination
        )
        guard buildResult.success, let builtPath = buildResult.productPath else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(buildResult)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return CallTool.Result(content: [.text("Build failed:\n\(json)")], isError: true)
        }
        productPath = builtPath
        buildDuration = buildResult.duration
    }

    // Install + Launch
    let udid = try await SimulatorManager.live.bootedUDID()
    if let productPath {
        try await runner.install(bundleId: bundleId, productPath: productPath, udid: udid)
    }
    try await runner.launch(bundleId: bundleId, udid: udid)

    let msg = skipBuild || appPath != nil
        ? "App launched: \(bundleId) on \(simName) (build skipped)"
        : "App launched: \(bundleId) on \(simName) (build: \(String(format: "%.1f", buildDuration))s)"
    return CallTool.Result(content: [.text(msg)])
}

func handleTest(arguments: [String: Value]?, config: LassoConfig?) async throws -> CallTool.Result {
    let scheme = arguments?["scheme"]?.stringValue ?? config?.scheme
    guard let scheme else {
        return CallTool.Result(content: [.text("Error: 'scheme' is required (provide it or set it in lasso.yml)")], isError: true)
    }

    let workspace = arguments?["workspace"]?.stringValue ?? config?.workspace
    let project = arguments?["project"]?.stringValue ?? config?.project
    let simName = config?.simulator ?? "iPhone 16"
    let destination = "platform=iOS Simulator,name=\(simName)"

    let result = try await XcodeBuildRunner().test(
        scheme: scheme, workspace: workspace, project: project, destination: destination
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    let json = String(data: data, encoding: .utf8) ?? "{}"
    return CallTool.Result(content: [.text(json)], isError: !result.success)
}
