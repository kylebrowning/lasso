import ArgumentParser

@available(macOS 15, *)
public struct LassoCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lasso",
        abstract: "iOS development CLI — build, test, automate, and diff.",
        version: "0.1.0",
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
        ]
    )

    public init() {}
}
