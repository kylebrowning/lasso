import ArgumentParser
import LassoCore
import Foundation

@available(macOS 15, *)
struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a screenshot of the simulator."
    )

    @Option(name: .shortAndLong, help: "Output file path (default: screenshot.png in current dir)")
    var output: String?

    @Flag(name: .long, help: "Output as base64 instead of saving to file")
    var base64 = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let udid = try await SimulatorManager.live.bootedUDID()
        let data = try await options.makeUIAutomation(udid: udid).screenshot()

        if base64 || options.json {
            let b64 = data.base64EncodedString()
            if options.json {
                print(try JSONOutput.string(["format": "png", "encoding": "base64", "data": b64]))
            } else {
                print(b64)
            }
        } else {
            let path = output ?? "screenshot.png"
            let url = URL(fileURLWithPath: path)
            try data.write(to: url)
            print("Screenshot saved to \(path) (\(data.count) bytes)")
        }
    }
}
