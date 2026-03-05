import Foundation

// MARK: - DriverInfo

public struct DriverInfo: Codable, Sendable {
    public let xcodeVersion: String
    public let xcodeBuildVersion: String
    public let builtAt: String
    public let lassoVersion: String
}

// MARK: - DriverCache

public struct DriverCache: Sendable {
    public var isValid: @Sendable () async -> Bool
    public var cachedXCTestRunPath: @Sendable () -> String?
    public var cachedXCTestBundlePath: @Sendable () -> String?
    public var buildAndCache: @Sendable (String) async throws -> Void
    public var xctestrunPath: @Sendable () -> String

    public init(
        isValid: @escaping @Sendable () async -> Bool,
        cachedXCTestRunPath: @escaping @Sendable () -> String?,
        cachedXCTestBundlePath: @escaping @Sendable () -> String?,
        buildAndCache: @escaping @Sendable (String) async throws -> Void,
        xctestrunPath: @escaping @Sendable () -> String
    ) {
        self.isValid = isValid
        self.cachedXCTestRunPath = cachedXCTestRunPath
        self.cachedXCTestBundlePath = cachedXCTestBundlePath
        self.buildAndCache = buildAndCache
        self.xctestrunPath = xctestrunPath
    }
}

// MARK: - Live Implementation

extension DriverCache {
    static let cacheDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.lasso/driver"
    }()

    /// Build products directory inside cache — mirrors DerivedData/Build/Products/
    static let productsDir: String = {
        "\(cacheDir)/Products"
    }()

    static let infoPath: String = {
        "\(cacheDir)/driver-info.json"
    }()

    public static let live = DriverCache(
        isValid: {
            guard let info = loadInfo() else { return false }
            guard let xcodeVersion = await currentXcodeVersion() else { return false }
            return info.xcodeVersion == xcodeVersion.version
                && info.xcodeBuildVersion == xcodeVersion.build
        },
        cachedXCTestRunPath: {
            findXCTestRun(in: productsDir)
        },
        cachedXCTestBundlePath: {
            let path = "\(productsDir)/Debug-iphonesimulator/LassoDriverUITests-Runner.app/PlugIns/LassoDriverUITests.xctest"
            return FileManager.default.fileExists(atPath: path) ? path : nil
        },
        buildAndCache: { simulatorName in
            // Find the driver source
            let driverProjectPath = try DriverPathResolver.live.resolve()
            let destination = "platform=iOS Simulator,name=\(simulatorName)"

            // Build for testing
            let buildCmd = [
                "xcodebuild build-for-testing",
                "-project \(driverProjectPath)",
                "-scheme LassoDriverUITests",
                "-destination \"\(destination)\"",
            ].joined(separator: " ")
            _ = try await shell(buildCmd)

            // Find the DerivedData Build/Products directory
            let projectDir = URL(fileURLWithPath: driverProjectPath)
                .deletingLastPathComponent().lastPathComponent
            let productsSearch = try await shell(
                "find ~/Library/Developer/Xcode/DerivedData/\(projectDir.replacingOccurrences(of: " ", with: "*"))*/Build/Products -name '*.xctestrun' -maxdepth 1 | head -1"
            )
            let xctestrunPath = productsSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !xctestrunPath.isEmpty else {
                throw LassoError.commandFailed("Could not find .xctestrun file after build-for-testing", 1)
            }

            // The Products directory is the parent of the .xctestrun file
            let sourceProductsDir = URL(fileURLWithPath: xctestrunPath).deletingLastPathComponent().path

            // Clear and recreate cache
            let fm = FileManager.default
            if fm.fileExists(atPath: cacheDir) {
                try fm.removeItem(atPath: cacheDir)
            }
            try fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

            // Copy entire Products directory (contains Debug-iphonesimulator/ + .xctestrun)
            try fm.copyItem(atPath: sourceProductsDir, toPath: productsDir)

            // Write driver-info.json
            guard let xcodeVersion = await currentXcodeVersion() else {
                throw LassoError.commandFailed("Could not determine Xcode version", 1)
            }

            let info = DriverInfo(
                xcodeVersion: xcodeVersion.version,
                xcodeBuildVersion: xcodeVersion.build,
                builtAt: ISO8601DateFormatter().string(from: Date()),
                lassoVersion: "0.1.0"
            )
            let data = try JSONEncoder().encode(info)
            try data.write(to: URL(fileURLWithPath: infoPath))
        },
        xctestrunPath: {
            findXCTestRun(in: productsDir) ?? "\(productsDir)/LassoDriver.xctestrun"
        }
    )
}

// MARK: - Failing Implementation

extension DriverCache {
    public static let failing = DriverCache(
        isValid: { false },
        cachedXCTestRunPath: { nil },
        cachedXCTestBundlePath: { nil },
        buildAndCache: { _ in throw LassoError.commandFailed("DriverCache.failing: buildAndCache", 1) },
        xctestrunPath: { "" }
    )
}

// MARK: - Helpers

extension DriverCache {
    static func findXCTestRun(in directory: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        guard let file = contents.first(where: { $0.hasSuffix(".xctestrun") }) else {
            return nil
        }
        return "\(directory)/\(file)"
    }

    static func loadInfo() -> DriverInfo? {
        guard let data = FileManager.default.contents(atPath: infoPath) else { return nil }
        return try? JSONDecoder().decode(DriverInfo.self, from: data)
    }

    static func currentXcodeVersion() async -> (version: String, build: String)? {
        guard let output = try? await shell("xcodebuild -version") else { return nil }
        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else { return nil }
        // "Xcode 16.2" → "16.2"
        let version = lines[0].replacingOccurrences(of: "Xcode ", with: "").trimmingCharacters(in: .whitespaces)
        // "Build version 16C5032a" → "16C5032a"
        let build = lines[1].replacingOccurrences(of: "Build version ", with: "").trimmingCharacters(in: .whitespaces)
        return (version, build)
    }
}
