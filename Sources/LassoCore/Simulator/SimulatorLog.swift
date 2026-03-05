import Foundation

public struct LogEntry: Sendable, Codable {
    public let timestamp: String
    public let subsystem: String
    public let category: String
    public let process: String
    public let level: String
    public let message: String

    public init(timestamp: String, subsystem: String, category: String, process: String, level: String, message: String) {
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.level = level
        self.message = message
    }
}

public struct LogFilter: Sendable {
    public var subsystem: String?
    public var category: String?
    public var process: String?
    public var level: String?

    public init(subsystem: String? = nil, category: String? = nil, process: String? = nil, level: String? = nil) {
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.level = level
    }

    func predicate() -> String? {
        var clauses: [String] = []
        if let subsystem {
            clauses.append("subsystem == \"\(subsystem)\"")
        }
        if let category {
            clauses.append("category == \"\(category)\"")
        }
        if let process {
            clauses.append("processImagePath ENDSWITH \"\(process)\"")
        }
        return clauses.isEmpty ? nil : clauses.joined(separator: " AND ")
    }
}

public struct SimulatorLog: Sendable, Decodable {
    enum CodingKeys: CodingKey {}
    public init(from decoder: any Decoder) throws { self = .live }

    public var fetchRecent: @Sendable (_ udid: String, _ filter: LogFilter, _ last: String) async throws -> [LogEntry]
    public var stream: @Sendable (_ udid: String, _ filter: LogFilter, _ handler: @Sendable (String) -> Void) async throws -> Void

    public init(
        fetchRecent: @escaping @Sendable (_ udid: String, _ filter: LogFilter, _ last: String) async throws -> [LogEntry],
        stream: @escaping @Sendable (_ udid: String, _ filter: LogFilter, _ handler: @Sendable (String) -> Void) async throws -> Void
    ) {
        self.fetchRecent = fetchRecent
        self.stream = stream
    }
}

extension SimulatorLog {
    public static let live = SimulatorLog(
        fetchRecent: { udid, filter, last in
            var args = ["xcrun", "simctl", "spawn", udid, "log", "show",
                        "--style", "ndjson",
                        "--last", last]
            if let level = filter.level {
                args += ["--level", level]
            }
            if let predicate = filter.predicate() {
                args += ["--predicate", predicate]
            }
            let command = args.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
            let output = try await shell(command)
            return parseNDJSON(output)
        },
        stream: { udid, filter, handler in
            var args = ["xcrun", "simctl", "spawn", udid, "log", "stream",
                        "--style", "compact"]
            if let level = filter.level {
                args += ["--level", level]
            }
            if let predicate = filter.predicate() {
                args += ["--predicate", predicate]
            }
            let command = args.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            try process.run()

            let handle = pipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let line = String(data: data, encoding: .utf8) {
                    handler(line)
                }
            }
            process.waitUntilExit()
        }
    )
}

private func parseNDJSON(_ output: String) -> [LogEntry] {
    let decoder = JSONDecoder()
    return output
        .split(separator: "\n")
        .compactMap { line -> LogEntry? in
            guard let data = line.data(using: .utf8),
                  let raw = try? decoder.decode(RawLogEntry.self, from: data) else {
                return nil
            }
            return LogEntry(
                timestamp: raw.timestamp,
                subsystem: raw.subsystem ?? "",
                category: raw.category ?? "",
                process: raw.processImagePath?.components(separatedBy: "/").last ?? raw.senderImagePath?.components(separatedBy: "/").last ?? "",
                level: raw.messageType ?? "default",
                message: raw.eventMessage ?? ""
            )
        }
}

private struct RawLogEntry: Decodable {
    let timestamp: String
    let subsystem: String?
    let category: String?
    let processImagePath: String?
    let senderImagePath: String?
    let messageType: String?
    let eventMessage: String?
}
