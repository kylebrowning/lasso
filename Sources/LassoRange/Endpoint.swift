import Foundation

// MARK: - HTTP Method

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - Marker Types

public struct EmptyBody: Encodable, Sendable {}
public struct EmptyResponse: Decodable, Sendable {}

// MARK: - Endpoint

public struct Endpoint<Request: Encodable & Sendable, Response: Decodable & Sendable>: Sendable {
    public var path: String
    public var method: HTTPMethod
    public var body: Request?
    public var queryItems: [URLQueryItem]?

    public init(path: String, method: HTTPMethod, body: Request? = nil, queryItems: [URLQueryItem]? = nil) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
    }

    public func url(relativeTo baseURL: URL) -> URL {
        let base = baseURL.absoluteString.hasSuffix("/")
            ? baseURL.absoluteString
            : baseURL.absoluteString + "/"
        // Path segments are already percent-encoded by the endpoint definitions,
        // so we concatenate directly to avoid double-encoding.
        var components = URLComponents(string: base + path)!
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }
}
