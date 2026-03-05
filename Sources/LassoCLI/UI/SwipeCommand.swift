import ArgumentParser
import LassoCore

@available(macOS 15, *)
struct SwipeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swipe",
        abstract: "Swipe in a direction or between coordinates."
    )

    @Option(name: .long, help: "Direction: up, down, left, right")
    var direction: String?

    @Option(name: .long, help: "Start X")
    var startX: Double?

    @Option(name: .long, help: "Start Y")
    var startY: Double?

    @Option(name: .long, help: "End X")
    var endX: Double?

    @Option(name: .long, help: "End Y")
    var endY: Double?

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let udid = try await SimulatorManager.live.bootedUDID()
        let ui = options.makeUIAutomation(udid: udid)

        if let direction {
            guard let dir = SwipeDirection(rawValue: direction) else {
                throw LassoError.invalidArgument("Invalid direction: \(direction). Use: up, down, left, right")
            }
            try await ui.swipe(direction: dir)
            if options.json {
                print(try JSONOutput.string(["action": "swipe", "direction": direction]))
            } else {
                print("Swiped \(direction)")
            }
        } else if let sx = startX, let sy = startY, let ex = endX, let ey = endY {
            try await ui.swipe(startX: sx, startY: sy, endX: ex, endY: ey)
            if options.json {
                print(try JSONOutput.string(["action": "swipe", "startX": "\(sx)", "startY": "\(sy)", "endX": "\(ex)", "endY": "\(ey)"]))
            } else {
                print("Swiped from (\(sx), \(sy)) to (\(ex), \(ey))")
            }
        } else {
            throw LassoError.invalidArgument("Provide --direction or all of --start-x, --start-y, --end-x, --end-y")
        }
    }
}
