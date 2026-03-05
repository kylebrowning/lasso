import Foundation

public struct UIAutomation: Sendable {
    public let udid: String
    private let client: DriverClient

    public init(udid: String, driverClient: DriverClient = .live()) {
        self.udid = udid
        self.client = driverClient
    }

    // MARK: - Tap

    public func tap(label: String) async throws {
        try await client.tap(.label(label))
    }

    public func tap(x: Double, y: Double) async throws {
        try await client.tap(.coordinate(x: x, y: y))
    }

    // MARK: - Swipe

    public func swipe(direction: SwipeDirection) async throws {
        try await client.swipe(.direction(direction))
    }

    public func swipe(startX: Double, startY: Double, endX: Double, endY: Double) async throws {
        try await client.swipe(.coordinates(startX: startX, startY: startY, endX: endX, endY: endY))
    }

    // MARK: - Type

    public func type(_ text: String) async throws {
        try await client.typeText(text)
    }

    // MARK: - Screenshot

    public func screenshot() async throws -> Data {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("lasso_screenshot_\(UUID().uuidString).png")
        _ = try await shell("xcrun simctl io \(udid) screenshot \(tmpFile.path)")
        let data = try Data(contentsOf: tmpFile)
        try? FileManager.default.removeItem(at: tmpFile)
        return data
    }

    // MARK: - Accessibility

    public func hierarchy() async throws -> DriverNode {
        try await client.hierarchy()
    }

    public func accessibilityViolations() async throws -> [A11yViolation] {
        let tree = try await hierarchy()
        return tree.violations
    }
}
