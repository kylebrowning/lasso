import ArgumentParser
import GrantivaCore

@available(macOS 15, *)
public struct GrantivaCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "grantiva",
        abstract: "The Grantiva CLI for iOS developers.",
        version: grantivaVersion,
        subcommands: [
            BuildCommand.self,
            RunCommand.self,
            HierarchyCommand.self,
            CICommand.self,
            DiffCommand.self,
            AuthCommand.self,
            DoctorCommand.self,
            RunnerCommand.self,
            InitCommand.self,
            MCPCommand.self,
        ]
    )

    public init() {}
}
