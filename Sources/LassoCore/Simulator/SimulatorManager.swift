import Foundation

public struct SimulatorManager: Sendable, Decodable {
    public static let live = SimulatorManager()

    public init() {}

    public func listDevices() async throws -> [SimulatorDevice] {
        let output = try await shell("xcrun simctl list devices --json")
        guard let data = output.data(using: .utf8) else { return [] }
        let parsed = try JSONDecoder().decode(SimctlDeviceList.self, from: data)
        return parsed.allDevices
    }

    public func bootedDevice() async throws -> SimulatorDevice {
        let devices = try await listDevices()
        guard let booted = devices.first(where: { $0.isBooted }) else {
            throw LassoError.simulatorNotRunning
        }
        return booted
    }

    public func bootedUDID() async throws -> String {
        try await bootedDevice().udid
    }

    public func boot(nameOrUDID: String) async throws -> SimulatorDevice {
        let devices = try await listDevices()
        guard let device = devices.first(where: { $0.name == nameOrUDID || $0.udid == nameOrUDID }) else {
            throw LassoError.invalidArgument("Simulator not found: \"\(nameOrUDID)\"")
        }
        if !device.isBooted {
            _ = try await shell("xcrun simctl boot \(device.udid)")
        }
        return device
    }
}

// MARK: - simctl JSON Parsing

struct SimctlDeviceList: Decodable {
    let devices: [String: [SimctlDevice]]

    struct SimctlDevice: Decodable {
        let name: String
        let udid: String
        let state: String
        let isAvailable: Bool
    }

    var allDevices: [SimulatorDevice] {
        devices.flatMap { (runtime, devs) in
            devs.map { dev in
                SimulatorDevice(
                    name: dev.name,
                    udid: dev.udid,
                    state: dev.state,
                    runtime: runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: ""),
                    isAvailable: dev.isAvailable
                )
            }
        }
        .sorted { $0.name < $1.name }
    }
}
