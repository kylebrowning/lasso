import ArgumentParser
import Foundation
import LassoCore

@available(macOS 15, *)
struct AuthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage authentication with Lasso Range.",
        subcommands: [LoginCommand.self, StatusCommand.self, LogoutCommand.self]
    )

    // MARK: - Login

    struct LoginCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "login",
            abstract: "Authenticate with Lasso Range API."
        )

        @OptionGroup var options: GlobalOptions

        @Option(name: .long, help: "API key for Lasso Range (skip browser flow)")
        var apiKey: String?

        @Option(name: .long, help: "Base URL for Lasso Range API")
        var baseURL: String = LassoDefaults.apiBaseURL

        func run() async throws {
            if let apiKey {
                try await loginWithAPIKey(apiKey)
            } else {
                try await loginWithBrowser()
            }
        }

        // MARK: - Direct API key flow (CI / headless)

        private func loginWithAPIKey(_ apiKey: String) async throws {
            let meURL = URL(string: "\(baseURL)/auth/me")!
            var request = URLRequest(url: meURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LassoError.networkError("Invalid response", 0)
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw LassoError.notAuthenticated
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                throw LassoError.networkError(body, httpResponse.statusCode)
            }

            let meResponse = try JSONDecoder().decode(MeResponse.self, from: data)

            let credentials = AuthCredentials(
                apiKey: apiKey,
                baseURL: baseURL,
                email: meResponse.email
            )
            try AuthStore.live.save(credentials)

            if options.json {
                let result = LoginResult(
                    authenticated: true,
                    email: meResponse.email,
                    baseURL: baseURL,
                    apiKeyPrefix: meResponse.apiKeyPrefix
                )
                print(try JSONOutput.string(result))
            } else {
                print("Authenticated as \(meResponse.email)")
                print("API key: \(meResponse.apiKeyPrefix)...")
                print("Credentials saved to ~/.lasso/auth.json")
            }
        }

        // MARK: - Browser-based flow

        private func loginWithBrowser() async throws {
            // 1. Create a CLI session
            let sessionURL = URL(string: "\(baseURL)/auth/cli/sessions")!
            var createRequest = URLRequest(url: sessionURL)
            createRequest.httpMethod = "POST"
            createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            createRequest.setValue("application/json", forHTTPHeaderField: "Accept")

            let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)

            guard let createHTTP = createResponse as? HTTPURLResponse, createHTTP.statusCode == 200 else {
                throw LassoError.networkError("Failed to create auth session", (createResponse as? HTTPURLResponse)?.statusCode ?? 0)
            }

            let session = try JSONDecoder().decode(CreateSessionResponse.self, from: createData)

            // 2. Open browser
            let loginURL = "\(baseURL)/auth/cli?session=\(session.sessionId)"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [loginURL]
            try process.run()
            process.waitUntilExit()

            if !options.json {
                print("Opening browser to sign in...")
                print("If the browser doesn't open, visit: \(loginURL)")
                print("Waiting for authentication...")
            }

            // 3. Poll for completion
            let pollURL = URL(string: "\(baseURL)/auth/cli/sessions/\(session.sessionId)")!
            let timeout: TimeInterval = 300 // 5 minutes
            let interval: TimeInterval = 2
            let start = Date()

            while Date().timeIntervalSince(start) < timeout {
                try await Task.sleep(for: .seconds(interval))

                var pollRequest = URLRequest(url: pollURL)
                pollRequest.httpMethod = "GET"
                pollRequest.setValue("application/json", forHTTPHeaderField: "Accept")

                let (pollData, pollResponse) = try await URLSession.shared.data(for: pollRequest)

                guard let pollHTTP = pollResponse as? HTTPURLResponse, pollHTTP.statusCode == 200 else {
                    continue
                }

                let pollResult = try JSONDecoder().decode(PollSessionResponse.self, from: pollData)

                if pollResult.status == "complete",
                   let apiKey = pollResult.apiKey,
                   let email = pollResult.email
                {
                    let credentials = AuthCredentials(
                        apiKey: apiKey,
                        baseURL: baseURL,
                        email: email
                    )
                    try AuthStore.live.save(credentials)

                    let prefix = String(apiKey.prefix(8))

                    if options.json {
                        let result = LoginResult(
                            authenticated: true,
                            email: email,
                            baseURL: baseURL,
                            apiKeyPrefix: prefix
                        )
                        print(try JSONOutput.string(result))
                    } else {
                        print("Authenticated as \(email)")
                        print("API key: \(prefix)...")
                        print("Credentials saved to ~/.lasso/auth.json")
                    }
                    return
                }
            }

            // Timeout
            if options.json {
                throw LassoError.networkError("Authentication timed out", 0)
            } else {
                print("Authentication timed out after 5 minutes.")
                print("You can also authenticate directly: lasso auth login --api-key <key>")
                throw LassoError.networkError("Authentication timed out", 0)
            }
        }
    }

    // MARK: - Status

    struct StatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show current authentication status."
        )

        @OptionGroup var options: GlobalOptions

        func run() async throws {
            let env = ProcessInfo.processInfo.environment

            if let apiKey = env["LASSO_API_KEY"], !apiKey.isEmpty {
                let baseURL = env["LASSO_API_URL"] ?? LassoDefaults.apiBaseURL
                let prefix = String(apiKey.prefix(8))

                if options.json {
                    let result = StatusResult(
                        authenticated: true,
                        source: "env",
                        email: nil,
                        baseURL: baseURL,
                        apiKeyPrefix: prefix
                    )
                    print(try JSONOutput.string(result))
                } else {
                    print("Authenticated via environment variable")
                    print("  Base URL: \(baseURL)")
                    print("  API key:  \(prefix)...")
                }
                return
            }

            if let credentials = AuthStore.live.load() {
                let prefix = String(credentials.apiKey.prefix(8))

                if options.json {
                    let result = StatusResult(
                        authenticated: true,
                        source: "file",
                        email: credentials.email,
                        baseURL: credentials.baseURL,
                        apiKeyPrefix: prefix
                    )
                    print(try JSONOutput.string(result))
                } else {
                    print("Authenticated via ~/.lasso/auth.json")
                    if let email = credentials.email {
                        print("  Email:    \(email)")
                    }
                    print("  Base URL: \(credentials.baseURL)")
                    print("  API key:  \(prefix)...")
                }
                return
            }

            if options.json {
                let result = StatusResult(
                    authenticated: false,
                    source: nil,
                    email: nil,
                    baseURL: nil,
                    apiKeyPrefix: nil
                )
                print(try JSONOutput.string(result))
            } else {
                print("Not authenticated. Run: lasso auth login")
            }
        }
    }

    // MARK: - Logout

    struct LogoutCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logout",
            abstract: "Remove saved authentication credentials."
        )

        @OptionGroup var options: GlobalOptions

        func run() async throws {
            try AuthStore.live.delete()

            if options.json {
                let result = LogoutResult(success: true, message: "Credentials removed")
                print(try JSONOutput.string(result))
            } else {
                print("Logged out. Credentials removed from ~/.lasso/auth.json")
            }
        }
    }
}

// MARK: - Response Models (CLI session flow)

@available(macOS 15, *)
private struct CreateSessionResponse: Codable, Sendable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

@available(macOS 15, *)
private struct PollSessionResponse: Codable, Sendable {
    let status: String
    let apiKey: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case status
        case apiKey = "api_key"
        case email
    }
}

// MARK: - Response Models (API key validation)

@available(macOS 15, *)
private struct MeResponse: Codable, Sendable {
    let email: String
    let apiKeyPrefix: String

    enum CodingKeys: String, CodingKey {
        case email
        case apiKeyPrefix = "api_key_prefix"
    }
}

// MARK: - Output Models

@available(macOS 15, *)
private struct LoginResult: Codable, Sendable {
    let authenticated: Bool
    let email: String
    let baseURL: String
    let apiKeyPrefix: String
}

@available(macOS 15, *)
private struct StatusResult: Codable, Sendable {
    let authenticated: Bool
    let source: String?
    let email: String?
    let baseURL: String?
    let apiKeyPrefix: String?
}

@available(macOS 15, *)
private struct LogoutResult: Codable, Sendable {
    let success: Bool
    let message: String
}
