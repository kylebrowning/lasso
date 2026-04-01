import ArgumentParser
import Foundation
import GrantivaCore

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build and optionally install the app to a simulator.",
        subcommands: [BuildOnlyCommand.self, InstallCommand.self],
        defaultSubcommand: BuildOnlyCommand.self
    )
}

// MARK: - build

struct BuildOnlyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the app for a simulator using xcodebuild."
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var buildOptions: BuildOptions

    @Option(name: .long, help: "Scheme to build")
    var scheme: String?

    @Option(name: .long, help: "Simulator name")
    var simulator: String?

    func run() async throws {
        let config = try? GrantivaConfig.load()

        let resolved = try await ResolvedProject.resolve(
            schemeFlag: scheme,
            simulatorFlag: simulator,
            config: config,
            skipBuild: buildOptions.shouldSkipBuild
        )

        guard let buildScheme = resolved.scheme else {
            throw GrantivaError.invalidArgument(
                "No scheme specified. Pass --scheme or set it in grantiva.yml."
            )
        }

        let device = try await SimulatorManager.live.boot(nameOrUDID: resolved.simulator)
        let destination = "platform=iOS Simulator,name=\(device.name)"

        if !options.json {
            print("[grantiva] Building \(buildScheme) for \(device.name)...")
        }

        let result = try await XcodeBuildRunner().build(
            scheme: buildScheme,
            workspace: resolved.workspace,
            project: resolved.project,
            destination: destination,
            buildSettings: resolved.buildSettings
        )

        if options.json {
            print(try JSONOutput.string(result))
        } else {
            print(TableFormatter().formatBuild(result))
        }

        if !result.success {
            throw ExitCode.failure
        }
    }
}

// MARK: - install

struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Build, install, and launch the app on a simulator."
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var buildOptions: BuildOptions

    @Option(name: .long, help: "Scheme to build")
    var scheme: String?

    @Option(name: .long, help: "Simulator name")
    var simulator: String?

    @Option(name: .long, help: "Bundle identifier")
    var bundleId: String?

    func run() async throws {
        let config = try? GrantivaConfig.load()

        let resolvedBinary = try buildOptions.resolveAppBinary()
        defer { resolvedBinary?.cleanup() }

        let appBundleId = resolvedBinary.flatMap { AppBinaryResolver.bundleId(from: $0.appPath) }

        let resolved = try await ResolvedProject.resolve(
            schemeFlag: scheme,
            simulatorFlag: simulator,
            bundleIdFlag: bundleId,
            config: config,
            skipBuild: buildOptions.shouldSkipBuild,
            appBundleId: appBundleId
        )

        let device = try await SimulatorManager.live.boot(nameOrUDID: resolved.simulator)
        let destination = "platform=iOS Simulator,name=\(device.name)"

        var productPath: String?

        if buildOptions.shouldSkipInstall {
            if !options.json {
                print("[grantiva] Skipping build and install (--no-build)")
            }
        } else if let resolvedBinary {
            if !options.json {
                print("[grantiva] Using pre-built binary: \(URL(fileURLWithPath: resolvedBinary.appPath).lastPathComponent)")
            }
            productPath = resolvedBinary.appPath
        } else {
            guard let buildScheme = resolved.scheme else {
                throw GrantivaError.invalidArgument(
                    "No scheme specified. Pass --scheme, set it in grantiva.yml, or use --app-file to provide a pre-built binary."
                )
            }

            if !options.json {
                print("[grantiva] Building \(buildScheme) for \(device.name)...")
            }

            let result = try await XcodeBuildRunner().build(
                scheme: buildScheme,
                workspace: resolved.workspace,
                project: resolved.project,
                destination: destination,
                buildSettings: resolved.buildSettings
            )

            if !options.json {
                print(TableFormatter().formatBuild(result))
            }

            guard result.success else {
                if options.json {
                    print(try JSONOutput.string(result))
                }
                throw ExitCode.failure
            }

            productPath = result.productPath
        }

        guard let bid = resolved.bundleId else {
            throw GrantivaError.invalidArgument(
                "No bundle ID. Pass --bundle-id or set bundle_id in grantiva.yml."
            )
        }

        if let productPath {
            if !options.json {
                print("[grantiva] Installing \(bid)...")
            }
            try await XcodeBuildRunner().install(bundleId: bid, productPath: productPath, udid: device.udid)
        }

        if !options.json {
            print("[grantiva] Launching \(bid)...")
        }
        try await XcodeBuildRunner().launch(bundleId: bid, udid: device.udid)

        if options.json {
            print(try JSONOutput.string([
                "status": "launched",
                "bundle_id": bid,
                "simulator": device.name,
                "udid": device.udid,
            ]))
        } else {
            print("[grantiva] Done — \(bid) running on \(device.name)")
        }
    }
}
