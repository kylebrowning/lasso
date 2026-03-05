import ArgumentParser
import LassoCore

struct LogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Show or stream logs from the booted simulator."
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Filter by subsystem (e.g. com.example.myapp)")
    var subsystem: String?

    @Option(name: .long, help: "Filter by category")
    var category: String?

    @Option(name: .long, help: "Filter by process name")
    var process: String?

    @Option(name: .long, help: "Minimum log level: default, info, debug, error, fault")
    var level: String?

    @Option(name: .long, help: "Show recent logs instead of streaming (e.g. 5m, 1h, 30s)")
    var last: String?

    var simulatorManager: SimulatorManager = .live
    var simulatorLog: SimulatorLog = .live

    func run() async throws {
        let udid = try await simulatorManager.bootedUDID()
        let filter = LogFilter(subsystem: subsystem, category: category, process: process, level: level)

        if let last {
            let entries = try await simulatorLog.fetchRecent(udid, filter, last)
            if options.json {
                print(try JSONOutput.string(entries))
            } else {
                for entry in entries {
                    print(formatEntry(entry))
                }
                if entries.isEmpty {
                    print("No log entries found.")
                }
            }
        } else {
            try await simulatorLog.stream(udid, filter) { line in
                print(line, terminator: "")
            }
        }
    }

    private func formatEntry(_ entry: LogEntry) -> String {
        let src = [entry.subsystem, entry.category].filter { !$0.isEmpty }.joined(separator: ":")
        let prefix = src.isEmpty ? entry.process : src
        return "\(entry.timestamp) [\(entry.level)] \(prefix): \(entry.message)"
    }
}
