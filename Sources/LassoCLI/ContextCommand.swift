import ArgumentParser
import LassoCore
import Foundation

struct ContextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Dump project info for AI context."
    )

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        var context: [String: String] = [:]

        // Config
        if let config = try? LassoConfig.load() {
            if let s = config.scheme { context["scheme"] = s }
            if let w = config.workspace { context["workspace"] = w }
            if let p = config.project { context["project"] = p }
            if let sim = config.simulator { context["simulator"] = sim }
            if let bid = config.bundleId { context["bundle_id"] = bid }
        }

        // Booted simulator
        if let device = try? await SimulatorManager.live.bootedDevice() {
            context["booted_simulator"] = device.name
            context["booted_udid"] = device.udid
            context["booted_runtime"] = device.runtime
        }

        // Xcode version
        if let xcode = try? await shell("xcodebuild -version | head -1") {
            context["xcode_version"] = xcode
        }

        if options.json {
            print(try JSONOutput.string(context))
        } else {
            for (key, value) in context.sorted(by: { $0.key < $1.key }) {
                print("\(key): \(value)")
            }
        }
    }
}
