import CoreGraphics
import Foundation

// MARK: - Response / Request Types

public struct HealthResponse: Codable, Sendable {
    public let status: String
    public let bundleId: String
}

public struct DriverFrame: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum TapRequest: Sendable {
    case label(String)
    case coordinate(x: Double, y: Double)
}

public enum SwipeRequest: Sendable {
    case direction(SwipeDirection)
    case coordinates(startX: Double, startY: Double, endX: Double, endY: Double)
}

// MARK: - DriverNode

public struct DriverNode: Codable, Sendable, Equatable {
    public let role: String
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let frame: DriverFrame
    public let enabled: Bool
    public let children: [DriverNode]

    public init(
        role: String,
        label: String?,
        value: String?,
        identifier: String?,
        frame: DriverFrame,
        enabled: Bool,
        children: [DriverNode]
    ) {
        self.role = role
        self.label = label
        self.value = value
        self.identifier = identifier
        self.frame = frame
        self.enabled = enabled
        self.children = children
    }

    // MARK: - Pruning

    /// Returns a simplified tree keeping only nodes that are interactive,
    /// have a label/value/identifier, or are ancestors of such nodes.
    /// Container-only nodes (Other, Group, etc.) with no meaningful info are collapsed.
    public func pruned() -> DriverNode? {
        let interactiveRoles: Set<String> = [
            "Button", "Link", "Switch", "TextField", "SecureTextField",
            "Slider", "CheckBox", "PopUpButton", "Tab", "MenuItem",
            "SearchField", "TextArea", "Stepper", "Picker", "Toggle",
            "AXButton", "AXLink", "AXSwitch", "AXTextField",
            "AXSlider", "AXCheckBox", "AXPopUpButton",
        ]

        let isInteractive = interactiveRoles.contains(role)
        let hasInfo = (label != nil && !label!.isEmpty)
            || (value != nil && !value!.isEmpty)
            || (identifier != nil && !identifier!.isEmpty)

        let prunedChildren = children.compactMap { $0.pruned() }

        if isInteractive || hasInfo {
            return DriverNode(
                role: role, label: label, value: value, identifier: identifier,
                frame: frame, enabled: enabled, children: prunedChildren
            )
        }

        // Container with meaningful children — keep it
        if !prunedChildren.isEmpty {
            // If this container has only one child, skip this level
            if prunedChildren.count == 1 {
                return prunedChildren[0]
            }
            return DriverNode(
                role: role, label: nil, value: nil, identifier: nil,
                frame: frame, enabled: enabled, children: prunedChildren
            )
        }

        return nil
    }

    // MARK: - Search

    public func find(label searchLabel: String) -> DriverNode? {
        if self.label == searchLabel || self.value == searchLabel || self.identifier == searchLabel {
            return self
        }
        return children.lazy.compactMap { $0.find(label: searchLabel) }.first
    }

    // MARK: - Flatten

    public func flatten() -> [DriverNode] {
        [self] + children.flatMap { $0.flatten() }
    }

    // MARK: - Violations

    public var violations: [A11yViolation] {
        var found: [A11yViolation] = []
        let interactive = [
            "Button", "Link", "Switch", "TextField",
            "Slider", "CheckBox", "PopUpButton",
            // Also match AX-prefixed variants
            "AXButton", "AXLink", "AXSwitch", "AXTextField",
            "AXSlider", "AXCheckBox", "AXPopUpButton",
        ]
        if interactive.contains(role) {
            if label == nil || label!.isEmpty {
                found.append(A11yViolation(
                    rule: .missingLabel,
                    role: role,
                    frame: CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                ))
            }
            if frame.width > 0 && frame.height > 0 && (frame.width < 44 || frame.height < 44) {
                found.append(A11yViolation(
                    rule: .smallTapTarget,
                    role: role,
                    frame: CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                ))
            }
        }
        return found + children.flatMap(\.violations)
    }
}

// MARK: - Internal Encodable Helpers

private struct TapByLabel: Encodable {
    let label: String
}

private struct TapByCoordinate: Encodable {
    let x: Double
    let y: Double
}

private struct SwipeByDirection: Encodable {
    let direction: String
}

private struct SwipeByCoordinates: Encodable {
    let startX: Double
    let startY: Double
    let endX: Double
    let endY: Double
}

private struct TypeBody: Encodable {
    let text: String
}

private struct ActionResponse: Decodable {
    let action: String
    let success: Bool
}

private struct SourceResponse: Decodable {
    let source: String
}

private struct ScreenshotResponse: Decodable {
    let format: String
    let encoding: String
    let data: String
}

// MARK: - DriverClient

public struct DriverClient: Sendable {
    public var health: @Sendable () async throws -> HealthResponse
    public var hierarchy: @Sendable () async throws -> DriverNode
    public var tap: @Sendable (TapRequest) async throws -> Void
    public var swipe: @Sendable (SwipeRequest) async throws -> Void
    public var typeText: @Sendable (String) async throws -> Void
    public var pageSource: @Sendable () async throws -> String
    public var screenshot: @Sendable () async throws -> Data

    public init(
        health: @escaping @Sendable () async throws -> HealthResponse,
        hierarchy: @escaping @Sendable () async throws -> DriverNode,
        tap: @escaping @Sendable (TapRequest) async throws -> Void,
        swipe: @escaping @Sendable (SwipeRequest) async throws -> Void,
        typeText: @escaping @Sendable (String) async throws -> Void,
        pageSource: @escaping @Sendable () async throws -> String,
        screenshot: @escaping @Sendable () async throws -> Data
    ) {
        self.health = health
        self.hierarchy = hierarchy
        self.tap = tap
        self.swipe = swipe
        self.typeText = typeText
        self.pageSource = pageSource
        self.screenshot = screenshot
    }
}

// MARK: - Live Implementation

/// Fetch data from a driver endpoint via GET and decode the JSON response.
@Sendable
private func driverGet(baseURL: String, path: String) async throws -> Data {
    guard let url = URL(string: "\(baseURL)\(path)") else {
        throw LassoError.invalidArgument("Invalid URL: \(baseURL)\(path)")
    }
    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(from: url)
    } catch let error as URLError where error.code == .cannotConnectToHost {
        throw LassoError.driverNotRunning
    }
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw LassoError.commandFailed(
            "Driver request GET \(path) failed with status \(statusCode)",
            Int32(statusCode)
        )
    }
    return data
}

/// Send JSON to a driver endpoint via POST and return the raw response data.
@Sendable
private func driverPost(baseURL: String, path: String, body: Data) async throws -> Data {
    guard let url = URL(string: "\(baseURL)\(path)") else {
        throw LassoError.invalidArgument("Invalid URL: \(baseURL)\(path)")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await URLSession.shared.data(for: request)
    } catch let error as URLError where error.code == .cannotConnectToHost {
        throw LassoError.driverNotRunning
    }
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw LassoError.commandFailed(
            "Driver request POST \(path) failed with status \(statusCode)",
            Int32(statusCode)
        )
    }
    return data
}

extension DriverClient {
    public static func live(port: UInt16 = 22088) -> DriverClient {
        let baseURL = "http://localhost:\(port)"
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        return DriverClient(
            health: {
                let data = try await driverGet(baseURL: baseURL, path: "/health")
                return try decoder.decode(HealthResponse.self, from: data)
            },
            hierarchy: {
                let data = try await driverGet(baseURL: baseURL, path: "/hierarchy")
                return try decoder.decode(DriverNode.self, from: data)
            },
            tap: { request in
                let body: Data
                switch request {
                case .label(let label):
                    body = try encoder.encode(TapByLabel(label: label))
                case .coordinate(let x, let y):
                    body = try encoder.encode(TapByCoordinate(x: x, y: y))
                }
                _ = try await driverPost(baseURL: baseURL, path: "/tap", body: body)
            },
            swipe: { request in
                let body: Data
                switch request {
                case .direction(let dir):
                    body = try encoder.encode(SwipeByDirection(direction: dir.rawValue))
                case .coordinates(let startX, let startY, let endX, let endY):
                    body = try encoder.encode(
                        SwipeByCoordinates(startX: startX, startY: startY, endX: endX, endY: endY)
                    )
                }
                _ = try await driverPost(baseURL: baseURL, path: "/swipe", body: body)
            },
            typeText: { text in
                let body = try encoder.encode(TypeBody(text: text))
                _ = try await driverPost(baseURL: baseURL, path: "/type", body: body)
            },
            pageSource: {
                let data = try await driverGet(baseURL: baseURL, path: "/source")
                let resp = try decoder.decode(SourceResponse.self, from: data)
                return resp.source
            },
            screenshot: {
                let data = try await driverGet(baseURL: baseURL, path: "/screenshot")
                let resp = try decoder.decode(ScreenshotResponse.self, from: data)
                guard let pngData = Data(base64Encoded: resp.data) else {
                    throw LassoError.invalidImage
                }
                return pngData
            }
        )
    }
}

// MARK: - Failing Implementation

extension DriverClient {
    public static let failing = DriverClient(
        health: { throw LassoError.commandFailed("DriverClient.failing: health", 1) },
        hierarchy: { throw LassoError.commandFailed("DriverClient.failing: hierarchy", 1) },
        tap: { _ in throw LassoError.commandFailed("DriverClient.failing: tap", 1) },
        swipe: { _ in throw LassoError.commandFailed("DriverClient.failing: swipe", 1) },
        typeText: { _ in throw LassoError.commandFailed("DriverClient.failing: typeText", 1) },
        pageSource: { throw LassoError.commandFailed("DriverClient.failing: pageSource", 1) },
        screenshot: { throw LassoError.commandFailed("DriverClient.failing: screenshot", 1) }
    )
}
