import Foundation

/// HTTP client for communicating with WebDriverAgent via the W3C WebDriver protocol.
@available(macOS 15, *)
public struct WDAClient: Sendable {
    public var status: @Sendable () async throws -> WDAStatus
    public var hierarchy: @Sendable () async throws -> [String: Any]
    public var hierarchyXML: @Sendable () async throws -> String
    public var tapByLabel: @Sendable (_ label: String) async throws -> Void
    public var tapByCoordinate: @Sendable (_ x: Double, _ y: Double) async throws -> Void
    public var typeText: @Sendable (_ text: String) async throws -> Void
    public var swipe: @Sendable (_ direction: String) async throws -> Void
    public var screenshot: @Sendable () async throws -> Data

    public init(
        status: @escaping @Sendable () async throws -> WDAStatus,
        hierarchy: @escaping @Sendable () async throws -> [String: Any],
        hierarchyXML: @escaping @Sendable () async throws -> String,
        tapByLabel: @escaping @Sendable (_ label: String) async throws -> Void,
        tapByCoordinate: @escaping @Sendable (_ x: Double, _ y: Double) async throws -> Void,
        typeText: @escaping @Sendable (_ text: String) async throws -> Void,
        swipe: @escaping @Sendable (_ direction: String) async throws -> Void,
        screenshot: @escaping @Sendable () async throws -> Data
    ) {
        self.status = status
        self.hierarchy = hierarchy
        self.hierarchyXML = hierarchyXML
        self.tapByLabel = tapByLabel
        self.tapByCoordinate = tapByCoordinate
        self.typeText = typeText
        self.swipe = swipe
        self.screenshot = screenshot
    }
}

// MARK: - Supporting Types

public struct WDAStatus: Sendable {
    public let sessionId: String?
    public let ready: Bool

    public init(sessionId: String?, ready: Bool) {
        self.sessionId = sessionId
        self.ready = ready
    }
}

// MARK: - Live Implementation

@available(macOS 15, *)
extension WDAClient {
    public static func live(port: UInt16) -> WDAClient {
        let base = "http://localhost:\(port)"

        return WDAClient(
            status: {
                let url = URL(string: "\(base)/status")!
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw GrantivaError.commandFailed("WDA not responding on port \(port)", 1)
                }
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                let sessionId = json["sessionId"] as? String
                let ready = (json["value"] as? [String: Any])?["ready"] as? Bool ?? (sessionId != nil)
                return WDAStatus(sessionId: sessionId, ready: ready)
            },
            hierarchy: {
                let xml = try await fetchHierarchyXML(base: base)
                let parser = WDAHierarchyXMLParser(xml: xml)
                return parser.parse()
            },
            hierarchyXML: {
                try await fetchHierarchyXML(base: base)
            },
            tapByLabel: { label in
                let sessionId = try await resolveSessionId(base: base)
                // Find element by accessibility label using link text strategy
                let findBody: [String: Any] = ["using": "link text", "value": label]
                let findData = try JSONSerialization.data(withJSONObject: findBody)
                var findRequest = URLRequest(url: URL(string: "\(base)/session/\(sessionId)/elements")!)
                findRequest.httpMethod = "POST"
                findRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                findRequest.httpBody = findData

                let (responseData, findResponse) = try await URLSession.shared.data(for: findRequest)
                guard let findHttp = findResponse as? HTTPURLResponse, findHttp.statusCode == 200 else {
                    throw GrantivaError.elementNotFound(label)
                }

                let findJson = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] ?? [:]
                guard let elements = findJson["value"] as? [[String: Any]],
                      let first = elements.first,
                      let elementId = first["ELEMENT"] as? String ?? first.values.first as? String else {
                    throw GrantivaError.elementNotFound(label)
                }

                // Click the element
                var clickRequest = URLRequest(url: URL(string: "\(base)/session/\(sessionId)/element/\(elementId)/click")!)
                clickRequest.httpMethod = "POST"
                clickRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                clickRequest.httpBody = Data("{}".utf8)

                let (_, clickResponse) = try await URLSession.shared.data(for: clickRequest)
                guard let clickHttp = clickResponse as? HTTPURLResponse, clickHttp.statusCode == 200 else {
                    throw GrantivaError.commandFailed("Failed to tap element \"\(label)\"", 1)
                }
            },
            tapByCoordinate: { x, y in
                let sessionId = try await resolveSessionId(base: base)
                let body: [String: Any] = [
                    "actions": [
                        [
                            "type": "pointer",
                            "id": "finger1",
                            "parameters": ["pointerType": "touch"],
                            "actions": [
                                ["type": "pointerMove", "duration": 0, "x": Int(x), "y": Int(y)],
                                ["type": "pointerDown", "button": 0],
                                ["type": "pause", "duration": 100],
                                ["type": "pointerUp", "button": 0],
                            ],
                        ] as [String: Any]
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                var request = URLRequest(url: URL(string: "\(base)/session/\(sessionId)/actions")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = data

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw GrantivaError.commandFailed("Failed to tap at (\(x), \(y))", 1)
                }
            },
            typeText: { text in
                let sessionId = try await resolveSessionId(base: base)
                let body: [String: Any] = ["value": Array(text).map { String($0) }]
                let data = try JSONSerialization.data(withJSONObject: body)
                var request = URLRequest(url: URL(string: "\(base)/session/\(sessionId)/keys")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = data

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw GrantivaError.commandFailed("Failed to type text", 1)
                }
            },
            swipe: { direction in
                let sessionId = try await resolveSessionId(base: base)
                // Get window size first for calculating swipe coordinates
                let sizeUrl = URL(string: "\(base)/session/\(sessionId)/window/size")!
                let (sizeData, _) = try await URLSession.shared.data(from: sizeUrl)
                let sizeJson = try JSONSerialization.jsonObject(with: sizeData) as? [String: Any] ?? [:]
                let value = sizeJson["value"] as? [String: Any] ?? [:]
                let width = value["width"] as? Double ?? 390.0
                let height = value["height"] as? Double ?? 844.0

                let centerX = width / 2
                let centerY = height / 2

                let (startX, startY, endX, endY): (Double, Double, Double, Double)
                switch direction.lowercased() {
                case "up":
                    startX = centerX; startY = height * 0.7
                    endX = centerX; endY = height * 0.3
                case "down":
                    startX = centerX; startY = height * 0.3
                    endX = centerX; endY = height * 0.7
                case "left":
                    startX = width * 0.8; startY = centerY
                    endX = width * 0.2; endY = centerY
                case "right":
                    startX = width * 0.2; startY = centerY
                    endX = width * 0.8; endY = centerY
                default:
                    throw GrantivaError.invalidArgument("Invalid swipe direction \"\(direction)\". Use: up, down, left, right")
                }

                let body: [String: Any] = [
                    "actions": [
                        [
                            "type": "pointer",
                            "id": "finger1",
                            "parameters": ["pointerType": "touch"],
                            "actions": [
                                ["type": "pointerMove", "duration": 0, "x": Int(startX), "y": Int(startY)],
                                ["type": "pointerDown", "button": 0],
                                ["type": "pointerMove", "duration": 300, "x": Int(endX), "y": Int(endY)],
                                ["type": "pointerUp", "button": 0],
                            ],
                        ] as [String: Any]
                    ]
                ]
                let data = try JSONSerialization.data(withJSONObject: body)
                var request = URLRequest(url: URL(string: "\(base)/session/\(sessionId)/actions")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = data

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw GrantivaError.commandFailed("Failed to swipe \(direction)", 1)
                }
            },
            screenshot: {
                let sessionId = try await resolveSessionId(base: base)
                let url = URL(string: "\(base)/session/\(sessionId)/screenshot")!
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw GrantivaError.commandFailed("Failed to take screenshot via WDA", 1)
                }
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                guard let base64 = json["value"] as? String,
                      let imageData = Data(base64Encoded: base64) else {
                    throw GrantivaError.invalidImage
                }
                return imageData
            }
        )
    }

    // MARK: - Helpers

    private static func resolveSessionId(base: String) async throws -> String {
        let url = URL(string: "\(base)/status")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GrantivaError.commandFailed("WDA not responding", 1)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let sid = json["sessionId"] as? String {
            return sid
        }
        throw GrantivaError.commandFailed("No active WDA session", 1)
    }

    private static func fetchHierarchyXML(base: String) async throws -> String {
        let sessionId = try await resolveSessionId(base: base)
        let url = URL(string: "\(base)/session/\(sessionId)/source")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GrantivaError.commandFailed("Failed to get hierarchy from WDA", 1)
        }
        // WDA returns JSON with a "value" key containing the XML source
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = json["value"] as? String {
            return value
        }
        if let raw = String(data: data, encoding: .utf8) {
            return raw
        }
        throw GrantivaError.commandFailed("Empty hierarchy response", 1)
    }
}

// MARK: - Failing (Test) Implementation

@available(macOS 15, *)
extension WDAClient {
    public static let failing = WDAClient(
        status: { throw GrantivaError.commandFailed("WDAClient.failing", 1) },
        hierarchy: { throw GrantivaError.commandFailed("WDAClient.failing", 1) },
        hierarchyXML: { throw GrantivaError.commandFailed("WDAClient.failing", 1) },
        tapByLabel: { _ in throw GrantivaError.commandFailed("WDAClient.failing", 1) },
        tapByCoordinate: { _, _ in throw GrantivaError.commandFailed("WDAClient.failing", 1) },
        typeText: { _ in throw GrantivaError.commandFailed("WDAClient.failing", 1) },
        swipe: { _ in throw GrantivaError.commandFailed("WDAClient.failing", 1) },
        screenshot: { throw GrantivaError.commandFailed("WDAClient.failing", 1) }
    )
}

// MARK: - XML Parser for WDA Hierarchy

/// Parses the XML page source from WebDriverAgent into a dictionary tree.
/// Shared between WDAClient and CLI dump-hierarchy command.
public class WDAHierarchyXMLParser: NSObject, XMLParserDelegate {
    private let xml: String
    private var stack: [NSMutableDictionary] = []
    private var root: [String: Any] = [:]

    public init(xml: String) {
        self.xml = xml
    }

    public func parse() -> [String: Any] {
        guard let data = xml.data(using: .utf8) else { return [:] }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return root
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?,
                       attributes: [String: String]) {
        let node = NSMutableDictionary()
        node["type"] = elementName

        if let label = attributes["label"], !label.isEmpty {
            node["label"] = label
        }
        if let name = attributes["name"], !name.isEmpty {
            node["name"] = name
        }
        if let identifier = attributes["identifier"], !identifier.isEmpty {
            node["identifier"] = identifier
        }
        if let value = attributes["value"], !value.isEmpty {
            node["value"] = value
        }
        if let enabled = attributes["enabled"] {
            node["enabled"] = enabled == "true"
        }
        if let visible = attributes["visible"] {
            node["visible"] = visible == "true"
        }
        if let x = attributes["x"], let y = attributes["y"],
           let w = attributes["width"], let h = attributes["height"] {
            node["frame"] = ["x": x, "y": y, "width": w, "height": h]
        }

        node["children"] = NSMutableArray()

        if let parent = stack.last {
            (parent["children"] as? NSMutableArray)?.add(node)
        }

        stack.append(node)
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?) {
        if let finished = stack.popLast(), stack.isEmpty {
            root = finished as! [String: Any]
        }
    }
}
