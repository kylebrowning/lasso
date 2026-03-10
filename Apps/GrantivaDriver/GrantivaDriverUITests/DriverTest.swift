import XCTest

/// The "test" that starts the Grantiva driver HTTP server.
/// This test never completes — it blocks on the RunLoop, serving requests.
/// Kill the xcodebuild process to stop it.
final class DriverTest: XCTestCase {

    @MainActor
    func testStartDriver() throws {
        // Read bundle ID from environment if provided
        let bundleId = ProcessInfo.processInfo.environment["GRANTIVA_TARGET_BUNDLE_ID"]

        let handler = RequestHandler(bundleId: bundleId)

        // Read port from environment, default to 22088
        let port = UInt16(ProcessInfo.processInfo.environment["GRANTIVA_DRIVER_PORT"] ?? "22088") ?? 22088

        let server = try DriverServer(handler: handler, port: port)
        try server.start()

        print("[GrantivaDriver] Driver ready. Target: \(bundleId ?? "default app")")
        print("[GrantivaDriver] Endpoints: /health, /hierarchy, /tap, /swipe, /type, /source")

        // Block forever — the server handles requests on background queues
        RunLoop.current.run()
    }
}
