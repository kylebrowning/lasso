import ArgumentParser
import LassoCore

@available(macOS 15, *)
public struct LassoCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lasso",
        abstract: "iOS development CLI — build, test, automate, and diff.",
        version: lassoVersion,
        subcommands: [
            BuildCommand.self,
            RunCommand.self,
            TestCommand.self,
            SimCommand.self,
            DoctorCommand.self,
            InitCommand.self,
            ContextCommand.self,
            UICommand.self,
            DiffCommand.self,
            DriverCommand.self,
            MCPCommand.self,
            AuthCommand.self,
            CICommand.self,
            LogCommand.self,
            ScriptCommand.self,
        ]
    )

    public init() {}
}
