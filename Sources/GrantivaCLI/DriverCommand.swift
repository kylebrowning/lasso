import ArgumentParser
import GrantivaCore
import Foundation

@available(macOS 15, *)
struct RunnerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runner",
        abstract: "Manage the embedded UI automation runner.",
        subcommands: [
            RunnerInstallCommand.self,
            RunnerVersionCommand.self,
        ]
    )
}

// MARK: - Install

@available(macOS 15, *)
struct RunnerInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Extract or update the embedded runner binary."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        if !options.json {
            print("Extracting runner...")
        }

        let manager = RunnerManager.live
        try await manager.ensureAvailable()

        if options.json {
            print(try JSONOutput.string([
                "status": "installed",
                "path": manager.runnerPath(),
                "version": RunnerManager.runnerVersion,
            ]))
        } else {
            print("Runner installed at \(manager.runnerPath())")
            print("Version: \(RunnerManager.runnerVersion)")
        }
    }
}

// MARK: - Version

@available(macOS 15, *)
struct RunnerVersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show the embedded runner version."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        if options.json {
            print(try JSONOutput.string(["version": RunnerManager.runnerVersion]))
        } else {
            print("grantiva-runner \(RunnerManager.runnerVersion)")
        }
    }
}
