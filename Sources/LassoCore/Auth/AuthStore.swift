import Foundation

// MARK: - Defaults

public enum LassoDefaults {
    public static let apiBaseURL = "https://lasso.build"
}

// MARK: - AuthCredentials

public struct AuthCredentials: Codable, Sendable {
    public var apiKey: String
    public var baseURL: String
    public var email: String?

    public init(apiKey: String, baseURL: String, email: String? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.email = email
    }
}

// MARK: - AuthStore

public struct AuthStore: Sendable, Decodable {
    public init(from decoder: Decoder) throws { self = .live }
    public var load: @Sendable () -> AuthCredentials?
    public var save: @Sendable (AuthCredentials) throws -> Void
    public var delete: @Sendable () throws -> Void

    public init(
        load: @escaping @Sendable () -> AuthCredentials?,
        save: @escaping @Sendable (AuthCredentials) throws -> Void,
        delete: @escaping @Sendable () throws -> Void
    ) {
        self.load = load
        self.save = save
        self.delete = delete
    }
}

// MARK: - Live

extension AuthStore {
    static let authDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.lasso"
    }()

    static let authPath: String = {
        "\(authDir)/auth.json"
    }()

    public static let live = AuthStore(
        load: {
            guard let data = FileManager.default.contents(atPath: authPath) else { return nil }
            return try? JSONDecoder().decode(AuthCredentials.self, from: data)
        },
        save: { credentials in
            let fm = FileManager.default
            if !fm.fileExists(atPath: authDir) {
                try fm.createDirectory(atPath: authDir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(credentials)
            try data.write(to: URL(fileURLWithPath: authPath))
        },
        delete: {
            let fm = FileManager.default
            guard fm.fileExists(atPath: authPath) else { return }
            try fm.removeItem(atPath: authPath)
        }
    )
}

// MARK: - Failing

extension AuthStore {
    public static let failing = AuthStore(
        load: { nil },
        save: { _ in throw LassoError.commandFailed("AuthStore.failing: save", 1) },
        delete: { throw LassoError.commandFailed("AuthStore.failing: delete", 1) }
    )
}

// MARK: - Resolve

extension AuthStore {
    /// Resolves credentials from environment variables or auth.json file.
    /// Resolution order:
    /// 1. LASSO_API_KEY env var (with LASSO_API_URL or default)
    /// 2. ~/.lasso/auth.json file
    /// 3. nil
    public static func resolveCredentials() -> AuthCredentials? {
        let env = ProcessInfo.processInfo.environment

        // 1. Environment variable
        if let apiKey = env["LASSO_API_KEY"], !apiKey.isEmpty {
            let baseURL = env["LASSO_API_URL"] ?? LassoDefaults.apiBaseURL
            return AuthCredentials(apiKey: apiKey, baseURL: baseURL)
        }

        // 2. Auth file
        if let stored = live.load() {
            return stored
        }

        // 3. Not authenticated
        return nil
    }
}
