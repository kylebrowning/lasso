import Foundation

/// Manages the full driver lifecycle: cache validation, start, and stop.
/// Commands create a session, use its `ui` and `navigator` for automation, then call `stop()`.
public struct DriverSession: Sendable {
    public let manager: DriverManager
    public let ui: UIAutomation
    public let navigator: ScreenNavigator

    /// Start a driver session: validate cache, start the driver, return a ready-to-use session.
    public static func start(
        udid: String,
        bundleId: String?,
        simulatorName: String,
        port: UInt16 = 22088,
        cache: DriverCache = .live,
        navigator: ScreenNavigator = .live
    ) async throws -> DriverSession {
        let config = DriverConfig(
            targetBundleId: bundleId,
            simulatorName: simulatorName,
            port: port
        )
        let manager = DriverManager(cache: cache)
        try await manager.start(config)

        let client = DriverClient.live(port: port)
        let ui = UIAutomation(udid: udid, driverClient: client)
        return DriverSession(manager: manager, ui: ui, navigator: navigator)
    }

    public func captureAll(_ screens: [GrantivaConfig.Screen], _ outputDir: String) async throws -> [ScreenCapture] {
        try await navigator.captureAll(screens, ui, outputDir)
    }

    public func stop() async {
        try? await manager.stop()
    }
}
