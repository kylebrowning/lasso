import Foundation

public struct SimulatorDevice: Sendable, Codable, Equatable {
    public let name: String
    public let udid: String
    public let state: String
    public let runtime: String
    public let isAvailable: Bool

    public var isBooted: Bool { state == "Booted" }

    public init(name: String, udid: String, state: String, runtime: String, isAvailable: Bool) {
        self.name = name
        self.udid = udid
        self.state = state
        self.runtime = runtime
        self.isAvailable = isAvailable
    }
}
