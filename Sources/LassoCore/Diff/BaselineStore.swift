import Foundation

public struct BaselineStore: Sendable {
    public var save: @Sendable (String, Data) async throws -> String
    public var load: @Sendable (String) async throws -> Data?
    public var list: @Sendable () async throws -> [String]
    public var delete: @Sendable (String) async throws -> Void
    public var baselineDirectory: @Sendable () -> String

    public init(
        save: @escaping @Sendable (String, Data) async throws -> String,
        load: @escaping @Sendable (String) async throws -> Data?,
        list: @escaping @Sendable () async throws -> [String],
        delete: @escaping @Sendable (String) async throws -> Void,
        baselineDirectory: @escaping @Sendable () -> String
    ) {
        self.save = save
        self.load = load
        self.list = list
        self.delete = delete
        self.baselineDirectory = baselineDirectory
    }
}

// MARK: - Local

extension BaselineStore {
    public static func local(directory: String = ".lasso/baselines") -> BaselineStore {
        let dir = directory
        return BaselineStore(
            save: { screenName, data in
                let fm = FileManager.default
                if !fm.fileExists(atPath: dir) {
                    try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                }
                let path = "\(dir)/\(screenName).png"
                try data.write(to: URL(fileURLWithPath: path))
                return path
            },
            load: { screenName in
                let path = "\(dir)/\(screenName).png"
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return try Data(contentsOf: URL(fileURLWithPath: path))
            },
            list: {
                let fm = FileManager.default
                guard fm.fileExists(atPath: dir) else { return [] }
                let files = try fm.contentsOfDirectory(atPath: dir)
                return files
                    .filter { $0.hasSuffix(".png") }
                    .map { String($0.dropLast(4)) }
                    .sorted()
            },
            delete: { screenName in
                let path = "\(dir)/\(screenName).png"
                try FileManager.default.removeItem(atPath: path)
            },
            baselineDirectory: { dir }
        )
    }
}

// MARK: - Resolve

extension BaselineStore {
    /// Resolves the baseline store based on authentication state.
    /// If authenticated (via env or auth.json), returns a placeholder that LassoCLI
    /// should replace with a RangeClient-backed store. Falls back to local.
    public static func resolve(directory: String = ".lasso/baselines") -> BaselineStore {
        if AuthStore.resolveCredentials() != nil {
            // Caller (LassoCLI) should wire up RangeClient.asBaselineStore() instead.
            // This fallback returns local so library-only callers still work.
            return .local(directory: directory)
        }
        return .local(directory: directory)
    }
}

// MARK: - Failing

extension BaselineStore {
    public static let failing = BaselineStore(
        save: { _, _ in throw LassoError.commandFailed("BaselineStore.failing: save", 1) },
        load: { _ in throw LassoError.commandFailed("BaselineStore.failing: load", 1) },
        list: { throw LassoError.commandFailed("BaselineStore.failing: list", 1) },
        delete: { _ in throw LassoError.commandFailed("BaselineStore.failing: delete", 1) },
        baselineDirectory: { "/dev/null" }
    )
}
