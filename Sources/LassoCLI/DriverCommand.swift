import ArgumentParser
import LassoCore
import Foundation

@available(macOS 15, *)
struct DriverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "driver",
        abstract: "Manage the XCUITest driver for UI automation.",
        subcommands: [
            DriverBuildCommand.self,
            DriverStartCommand.self,
            DriverStopCommand.self,
        ]
    )
}

// MARK: - Build

@available(macOS 15, *)
struct DriverBuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the XCUITest driver and cache it globally."
    )

    @Option(name: .long, help: "Simulator name (default: booted simulator)")
    var simulator: String?

    @OptionGroup var options: GlobalOptions

    var simulatorManager: SimulatorManager = .live
    var driverCache: DriverCache = .live

    func run() async throws {
        let simName: String
        if let simulator {
            simName = simulator
        } else {
            let booted = try await simulatorManager.bootedDevice()
            simName = booted.name
        }

        if !options.json {
            print("Building driver for \(simName)...")
        }

        let cache = driverCache
        try await cache.buildAndCache(simName)

        if options.json {
            print(try JSONOutput.string([
                "status": "cached",
                "path": cache.xctestrunPath(),
                "simulator": simName,
            ]))
        } else {
            print("Driver cached at ~/.lasso/driver/")
            print("Cache is valid for the current Xcode version.")
        }
    }
}

// MARK: - Start

@available(macOS 15, *)
struct DriverStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the XCUITest driver server."
    )

    @Option(name: .long, help: "Bundle ID of the app to automate")
    var bundleId: String?

    @Option(name: .long, help: "Simulator name (default: booted simulator)")
    var simulator: String?

    @Option(name: .long, help: "Driver server port")
    var port: UInt16 = 22088

    @OptionGroup var options: GlobalOptions

    var simulatorManager: SimulatorManager = .live

    func run() async throws {
        // Resolve simulator
        let simName: String
        if let simulator {
            simName = simulator
        } else {
            let booted = try await simulatorManager.bootedDevice()
            simName = booted.name
        }

        let config = DriverConfig(
            targetBundleId: bundleId,
            simulatorName: simName,
            port: port
        )

        if !options.json {
            print("Starting driver (simulator: \(simName), port: \(port))...")
        }

        let manager = DriverManager()
        try await manager.start(config)

        if options.json {
            print(try JSONOutput.string([
                "status": "running",
                "port": "\(port)",
                "simulator": simName,
            ]))
        } else {
            print("Driver is running on port \(port)")
            print("Press Ctrl+C to stop")
        }

        // Block until interrupted
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            signal(SIGINT, SIG_IGN)
            sigint.setEventHandler {
                Task {
                    try? await manager.stop()
                    Foundation.exit(0)
                }
            }
            sigint.resume()
        }
    }
}

// MARK: - Stop

@available(macOS 15, *)
struct DriverStopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop a running driver (kills the xcodebuild process)."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        // Find and kill any running xcodebuild test-without-building for LassoDriverUITests
        let output = try await shell("pgrep -f 'xcodebuild.*LassoDriverUITests' || true")
        let pids = output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        if pids.isEmpty {
            if options.json {
                print(try JSONOutput.string(["status": "not_running"]))
            } else {
                print("No running driver found.")
            }
            return
        }

        for pid in pids {
            _ = try? await shell("kill \(pid)")
        }

        if options.json {
            print(try JSONOutput.string(["status": "stopped", "pids": pids.map(String.init).joined(separator: ",")]))
        } else {
            print("Stopped driver (PID: \(pids.map(String.init).joined(separator: ", ")))")
        }
    }
}
