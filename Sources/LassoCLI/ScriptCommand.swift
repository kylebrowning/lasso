import ArgumentParser
import Foundation
import LassoCore
import Yams

@available(macOS 15, *)
struct ScriptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "script",
        abstract: "Run a sequence of UI actions from a YAML file."
    )

    @Argument(help: "Path to a YAML script file")
    var file: String

    @Option(name: .long, help: "Directory to save screenshots (default: ./lasso-screenshots)")
    var output: String = "./lasso-screenshots"

    @OptionGroup var options: GlobalOptions

    var simulatorManager: SimulatorManager = .live

    func run() async throws {
        let path = (file as NSString).standardizingPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw LassoError.invalidArgument("Script file not found: \(path)")
        }

        let yaml = try String(contentsOfFile: path, encoding: .utf8)
        let steps = try YAMLDecoder().decode([ScriptStep].self, from: yaml)

        let udid = try await simulatorManager.bootedUDID()
        let ui = options.makeUIAutomation(udid: udid)

        let result = try await ScriptRunner().run(
            steps: steps,
            ui: ui,
            outputDir: output,
            log: { msg in
                if !options.json { print(msg) }
            }
        )

        if options.json {
            print(try JSONOutput.string(result))
        } else {
            let ok = result.steps.filter { $0.status == "ok" }.count
            print("\nCompleted \(ok)/\(result.steps.count) steps in \(String(format: "%.1f", result.duration))s")
        }
    }
}
