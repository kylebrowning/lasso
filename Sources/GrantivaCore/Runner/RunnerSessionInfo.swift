import Foundation

/// Shared session state persisted to `.grantiva/session.json`.
public struct RunnerSessionInfo: Codable, Sendable {
    public let pid: Int32
    public let wdaPort: UInt16
    public let bundleId: String
    public let udid: String
    public let startedAt: Date

    public static let path = ".grantiva/session.json"

    public init(pid: Int32, wdaPort: UInt16, bundleId: String, udid: String, startedAt: Date) {
        self.pid = pid
        self.wdaPort = wdaPort
        self.bundleId = bundleId
        self.udid = udid
        self.startedAt = startedAt
    }

    public func write() throws {
        let dir = (Self.path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: URL(fileURLWithPath: Self.path))
    }

    public static func load() throws -> RunnerSessionInfo {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(RunnerSessionInfo.self, from: data)
    }

    public static func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Check if the session process is still alive.
    public var isAlive: Bool {
        kill(pid, 0) == 0
    }
}
