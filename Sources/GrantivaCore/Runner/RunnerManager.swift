import Foundation

/// Manages the embedded grantiva-runner binary: extraction, caching, and version validation.
public struct RunnerManager: Sendable, Decodable {
    public init(from decoder: Decoder) throws { self = .live }

    public var ensureAvailable: @Sendable () async throws -> Void
    public var runnerPath: @Sendable () -> String
    public var runnerDir: @Sendable () -> String

    public init(
        ensureAvailable: @escaping @Sendable () async throws -> Void,
        runnerPath: @escaping @Sendable () -> String,
        runnerDir: @escaping @Sendable () -> String
    ) {
        self.ensureAvailable = ensureAvailable
        self.runnerPath = runnerPath
        self.runnerDir = runnerDir
    }
}

extension RunnerManager {
    public static let runnerVersion = "1.1.12-grantiva.2"

    static let baseDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.grantiva/runner"
    }()

    public static let binaryPath: String = {
        "\(baseDir)/grantiva-runner"
    }()

    static let versionFilePath: String = {
        "\(baseDir)/version"
    }()

    static let cacheDir: String = {
        "\(baseDir)/cache"
    }()

    /// Returns the resource name for the current CPU architecture.
    private static var archResourceName: String {
        #if arch(arm64)
        return "grantiva-runner-arm64"
        #elseif arch(x86_64)
        return "grantiva-runner-amd64"
        #else
        return "grantiva-runner-arm64"
        #endif
    }

    public static let live = RunnerManager(
        ensureAvailable: {
            let fm = FileManager.default

            // Check if already extracted and version matches
            if fm.fileExists(atPath: binaryPath),
               let versionData = fm.contents(atPath: versionFilePath),
               let version = String(data: versionData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               version == runnerVersion {
                return
            }

            // Extract from embedded resource (arch-specific)
            guard let tarURL = Bundle.module.url(forResource: archResourceName, withExtension: "tar.gz") else {
                throw GrantivaError.runnerNotFound
            }

            // Preserve WDA build cache across updates
            let hadCache = fm.fileExists(atPath: cacheDir)
            let tempCache = "\(baseDir)-cache-\(UUID().uuidString)"
            if hadCache {
                try fm.moveItem(atPath: cacheDir, toPath: tempCache)
            }

            // Clean and recreate
            if fm.fileExists(atPath: baseDir) {
                try fm.removeItem(atPath: baseDir)
            }
            try fm.createDirectory(atPath: baseDir, withIntermediateDirectories: true)

            // Extract tar.gz
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", tarURL.path, "-C", baseDir]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                // Restore cache on failure
                if hadCache { try? fm.moveItem(atPath: tempCache, toPath: cacheDir) }
                throw GrantivaError.commandFailed("Failed to extract runner binary", process.terminationStatus)
            }

            // Restore WDA build cache
            if hadCache {
                if fm.fileExists(atPath: cacheDir) {
                    try? fm.removeItem(atPath: cacheDir)
                }
                try fm.moveItem(atPath: tempCache, toPath: cacheDir)
            }

            // Make binary executable
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath)

            // Write version marker
            try runnerVersion.write(toFile: versionFilePath, atomically: true, encoding: .utf8)
        },
        runnerPath: { binaryPath },
        runnerDir: { baseDir }
    )
}

extension RunnerManager {
    public static let failing = RunnerManager(
        ensureAvailable: { throw GrantivaError.runnerNotFound },
        runnerPath: { "" },
        runnerDir: { "" }
    )
}
