import ArgumentParser
import LassoCore

@available(macOS 15, *)
struct TapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tap",
        abstract: "Tap an element by label or coordinates."
    )

    @Option(name: .long, help: "Accessibility label to tap")
    var label: String?

    @Option(name: .shortAndLong, help: "X coordinate")
    var x: Double?

    @Option(name: .shortAndLong, help: "Y coordinate")
    var y: Double?

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let udid = try await SimulatorManager().bootedUDID()
        let ui = options.makeUIAutomation(udid: udid)

        if let label {
            try await ui.tap(label: label)
            if options.json {
                print(try JSONOutput.string(["action": "tap", "label": label]))
            } else {
                print("Tapped \"\(label)\"")
            }
        } else if let x, let y {
            try await ui.tap(x: x, y: y)
            if options.json {
                print(try JSONOutput.string(["action": "tap", "x": "\(x)", "y": "\(y)"]))
            } else {
                print("Tapped (\(x), \(y))")
            }
        } else {
            throw LassoError.invalidArgument("Provide --label or both --x and --y")
        }
    }
}
