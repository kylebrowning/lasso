import ArgumentParser
import LassoCore

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Option(name: .long, help: "Driver server port (default: 22088)")
    var driverPort: UInt16 = 22088

    func makeUIAutomation(udid: String) -> UIAutomation {
        UIAutomation(udid: udid, driverClient: .live(port: driverPort))
    }
}
