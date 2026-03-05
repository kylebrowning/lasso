import ArgumentParser
import LassoCore

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the Xcode project."
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Scheme to build")
    var scheme: String?

    @Option(name: .long, help: "Workspace path")
    var workspace: String?

    @Option(name: .long, help: "Project path")
    var project: String?

    @Option(name: .long, help: "Simulator name for destination")
    var simulator: String?

    func run() async throws {
        let config = try? LassoConfig.load()
        let schemeName = scheme ?? config?.scheme
        guard let schemeName else {
            throw LassoError.invalidArgument("No scheme specified. Pass --scheme or set it in lasso.yml")
        }
        let ws = workspace ?? config?.workspace
        let proj = project ?? config?.project
        let sim = simulator ?? config?.simulator ?? "iPhone 16"
        let destination = "platform=iOS Simulator,name=\(sim)"

        let result = try await XcodeBuildRunner().build(
            scheme: schemeName, workspace: ws, project: proj, destination: destination
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
