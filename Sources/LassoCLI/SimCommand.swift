import ArgumentParser
import LassoCore

struct SimCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sim",
        abstract: "Manage iOS simulators.",
        subcommands: [ListCommand.self, BootCommand.self]
    )

    struct ListCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List available simulators."
        )

        @OptionGroup var options: GlobalOptions

        @Flag(name: .long, help: "Show only available simulators")
        var available = false

        func run() async throws {
            var devices = try await SimulatorManager().listDevices()
            if available {
                devices = devices.filter(\.isAvailable)
            }

            if options.json {
                print(try JSONOutput.string(devices))
            } else {
                print(TableFormatter().formatDevices(devices))
            }
        }
    }

    struct BootCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "boot",
            abstract: "Boot a simulator by name or UDID."
        )

        @Argument(help: "Simulator name or UDID")
        var nameOrUDID: String

        @OptionGroup var options: GlobalOptions

        func run() async throws {
            let device = try await SimulatorManager().boot(nameOrUDID: nameOrUDID)

            if options.json {
                print(try JSONOutput.string(device))
            } else {
                print("Booted \(device.name) (\(device.udid))")
            }
        }
    }
}
