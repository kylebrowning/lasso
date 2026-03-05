import ArgumentParser
import LassoCore

@available(macOS 15, *)
struct TypeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into the focused field."
    )

    @Argument(help: "Text to type")
    var text: String

    @OptionGroup var options: GlobalOptions

    var simulatorManager: SimulatorManager = .live

    func run() async throws {
        let udid = try await simulatorManager.bootedUDID()
        try await options.makeUIAutomation(udid: udid).type(text)

        if options.json {
            print(try JSONOutput.string(["action": "type", "text": text]))
        } else {
            print("Typed \"\(text)\"")
        }
    }
}
