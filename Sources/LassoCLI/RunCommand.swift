import ArgumentParser
import LassoCore

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Build, install, and launch on simulator."
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var buildOptions: BuildOptions

    @Option(name: .long, help: "Scheme to build")
    var scheme: String?

    @Option(name: .long, help: "Simulator name")
    var simulator: String?

    var simulatorManager: SimulatorManager = .live

    func run() async throws {
        let config = try? LassoConfig.load()
        let schemeName = scheme ?? config?.scheme
        guard let schemeName else {
            throw LassoError.invalidArgument("No scheme specified. Pass --scheme or set it in lasso.yml")
        }
        let sim = simulator ?? config?.simulator ?? "iPhone 16"

        // Boot simulator if needed
        let device = try await simulatorManager.boot(nameOrUDID: sim)
        let destination = "platform=iOS Simulator,name=\(device.name)"

        var productPath: String?

        if let resolvedPath = try await buildOptions.resolveProductPath(
            scheme: schemeName, workspace: config?.workspace,
            project: config?.project, destination: destination
        ) {
            if !options.json {
                print("Skipping build — using \(resolvedPath)")
            }
            productPath = resolvedPath
        } else {
            let buildResult = try await XcodeBuildRunner().build(
                scheme: schemeName, workspace: config?.workspace, project: config?.project, destination: destination
            )

            if !buildResult.success {
                if options.json {
                    print(try JSONOutput.string(buildResult))
                } else {
                    print(TableFormatter().formatBuild(buildResult))
                }
                throw ExitCode.failure
            }
            productPath = buildResult.productPath
        }

        // Install and launch
        if let bundleId = config?.bundleId {
            if let productPath {
                try await XcodeBuildRunner().install(bundleId: bundleId, productPath: productPath, udid: device.udid)
            }
            try await XcodeBuildRunner().launch(bundleId: bundleId, udid: device.udid)
        }

        if options.json {
            let status: [String: String] = ["status": "running", "simulator": device.name, "udid": device.udid]
            print(try JSONOutput.string(status))
        } else {
            print("Running \(schemeName) on \(device.name)")
        }
    }
}
