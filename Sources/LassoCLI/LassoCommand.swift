import ArgumentParser
import LassoCore

@available(macOS 15, *)
public struct LassoCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lasso",
        abstract: "Visual regression CI for iOS.",
        version: lassoVersion,
        subcommands: [
            CICommand.self,
            DiffCommand.self,
            AuthCommand.self,
            DoctorCommand.self,
            DriverCommand.self,
            InitCommand.self,
        ]
    )

    public init() {}
}
