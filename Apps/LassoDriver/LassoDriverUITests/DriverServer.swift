import Foundation
import Network

/// Lightweight HTTP server using NWListener.
/// Runs in the XCUITest process, handles requests from the lasso CLI.
final class DriverServer: @unchecked Sendable {
    let port: UInt16
    private var listener: NWListener?
    private let handler: RequestHandler

    init(handler: RequestHandler, port: UInt16 = 22088) {
        self.handler = handler
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        let serverPort = port
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[LassoDriver] Server listening on port \(serverPort)")
            case .failed(let error):
                print("[LassoDriver] Server failed: \(error)")
            default:
                break
            }
        }
        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveFullRequest(on: connection, accumulated: Data())
    }

    /// Accumulate data until we have a complete HTTP request (headers + body based on Content-Length).
    private func receiveFullRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            // Try to parse — check if we have the full request
            if let requestString = String(data: buffer, encoding: .utf8),
               self.isRequestComplete(requestString) {
                // Dispatch to main thread for XCUIApplication safety
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let response = self.route(request: requestString)
                        let httpResponse = self.formatHTTPResponse(
                            body: response.body,
                            status: response.status,
                            contentType: response.contentType
                        )
                        connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    }
                }
            } else if isComplete || error != nil {
                // Connection closed before full request — try to handle what we have
                if let requestString = String(data: buffer, encoding: .utf8), !requestString.isEmpty {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            let response = self.route(request: requestString)
                            let httpResponse = self.formatHTTPResponse(
                                body: response.body,
                                status: response.status,
                                contentType: response.contentType
                            )
                            connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in
                                connection.cancel()
                            })
                        }
                    }
                } else {
                    connection.cancel()
                }
            } else {
                // Need more data
                self.receiveFullRequest(on: connection, accumulated: buffer)
            }
        }
    }

    /// Check if we've received the complete HTTP request by looking at Content-Length.
    private func isRequestComplete(_ request: String) -> Bool {
        // Find the blank line separating headers from body
        guard let headerEndRange = request.range(of: "\r\n\r\n") else {
            return false // Haven't received all headers yet
        }

        let headers = String(request[request.startIndex..<headerEndRange.lowerBound])

        // Find Content-Length header
        let lines = headers.components(separatedBy: "\r\n")
        var contentLength = 0
        for line in lines {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
                break
            }
        }

        if contentLength == 0 {
            return true // No body expected (GET requests)
        }

        // Check if we have the full body
        let bodyStart = request[headerEndRange.upperBound...]
        return bodyStart.utf8.count >= contentLength
    }

    struct Response {
        let status: Int
        let body: String
        let contentType: String

        static func json(_ body: String, status: Int = 200) -> Response {
            Response(status: status, body: body, contentType: "application/json")
        }

        static func error(_ message: String, status: Int = 400) -> Response {
            json("{\"error\":\"\(message)\"}", status: status)
        }
    }

    @MainActor private func route(request: String) -> Response {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .error("Invalid request", status: 400)
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return .error("Invalid request line", status: 400)
        }

        let method = parts[0]
        let path = parts[1]

        // Extract body (everything after the empty line)
        let body: String?
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines[(emptyLineIndex + 1)...]
            let joined = bodyLines.joined(separator: "\r\n")
            body = joined.isEmpty ? nil : joined
        } else {
            body = nil
        }

        switch (method, path) {
        case ("GET", "/health"):
            return handler.health()
        case ("GET", "/hierarchy"):
            return handler.hierarchy()
        case ("POST", "/tap"):
            return handler.tap(body: body)
        case ("POST", "/swipe"):
            return handler.swipe(body: body)
        case ("POST", "/type"):
            return handler.typeText(body: body)
        case ("GET", "/source"):
            return handler.pageSource()
        default:
            return .error("Not found: \(method) \(path)", status: 404)
        }
    }

    private func formatHTTPResponse(body: String, status: Int, contentType: String) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        return """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
    }
}
