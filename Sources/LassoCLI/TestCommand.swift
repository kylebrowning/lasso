import ArgumentParser
import LassoCore

struct TestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run tests with structured output."
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Scheme to test")
    var scheme: String?

    @Option(name: .long, help: "Simulator name")
    var simulator: String?

    func run() async throws {
        let config = try? LassoConfig.load()
        let schemeName = scheme ?? config?.scheme
        guard let schemeName else {
            throw LassoError.invalidArgument("No scheme specified. Pass --scheme or set it in lasso.yml")
        }
        let sim = simulator ?? config?.simulator ?? "iPhone 16"
        let destination = "platform=iOS Simulator,name=\(sim)"

        let result = try await XcodeBuildRunner().test(
            scheme: schemeName, workspace: config?.workspace, project: config?.project, destination: destination
        )

        if options.json {
            print(try JSONOutput.string(result))
        } else {
            print(TableFormatter().formatTests(result))
        }

        if !result.success {
            throw ExitCode.failure
        }
    }
}
