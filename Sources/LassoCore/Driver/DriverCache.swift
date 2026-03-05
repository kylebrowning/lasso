import Foundation

// MARK: - DriverInfo

public struct DriverInfo: Codable, Sendable {
    public let xcodeVersion: String
    public let xcodeBuildVersion: String
    public let builtAt: String
    public let lassoVersion: String
}

// MARK: - DriverCache

public struct DriverCache: Sendable, Decodable {
    public init(from decoder: Decoder) throws { self = .live }
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
            let xcodeMatches = info.xcodeVersion == xcodeVersion.version
                && info.xcodeBuildVersion == xcodeVersion.build
            if xcodeMatches { return true }
            // If source project isn't available (installed via brew/mint),
            // accept any cached driver for the same lasso version
            let hasSource = (try? DriverPathResolver.live.resolve()) != nil
            if !hasSource && info.lassoVersion == lassoVersion {
                return true
            }
            return false
        },
        cachedXCTestRunPath: {
            findXCTestRun(in: productsDir)
        },
        cachedXCTestBundlePath: {
            let path = "\(productsDir)/Debug-iphonesimulator/LassoDriverUITests-Runner.app/PlugIns/LassoDriverUITests.xctest"
            return FileManager.default.fileExists(atPath: path) ? path : nil
        },
        buildAndCache: { simulatorName in
            // Try to find the driver source project locally
            if let driverProjectPath = try? DriverPathResolver.live.resolve() {
                try await buildFromSource(driverProjectPath, simulatorName: simulatorName)
            } else {
                try await downloadPrebuilt()
            }
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

// MARK: - Build from Source

extension DriverCache {
    static func buildFromSource(_ driverProjectPath: String, simulatorName: String) async throws {
        let destination = "platform=iOS Simulator,name=\(simulatorName)"

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

        let sourceProductsDir = URL(fileURLWithPath: xctestrunPath).deletingLastPathComponent().path

        let fm = FileManager.default
        if fm.fileExists(atPath: cacheDir) {
            try fm.removeItem(atPath: cacheDir)
        }
        try fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        try fm.copyItem(atPath: sourceProductsDir, toPath: productsDir)

        guard let xcodeVersion = await currentXcodeVersion() else {
            throw LassoError.commandFailed("Could not determine Xcode version", 1)
        }

        let info = DriverInfo(
            xcodeVersion: xcodeVersion.version,
            xcodeBuildVersion: xcodeVersion.build,
            builtAt: ISO8601DateFormatter().string(from: Date()),
            lassoVersion: lassoVersion
        )
        let data = try JSONEncoder().encode(info)
        try data.write(to: URL(fileURLWithPath: infoPath))
    }
}

// MARK: - Download Prebuilt

extension DriverCache {
    static let driverAssetName = "lasso-driver-\(lassoVersion)-macos.tar.gz"
    static let downloadURL = "https://github.com/kylebrowning/lasso/releases/download/\(lassoVersion)/\(driverAssetName)"

    static func downloadPrebuilt() async throws {
        let fm = FileManager.default

        // Clear and recreate cache dir
        if fm.fileExists(atPath: cacheDir) {
            try fm.removeItem(atPath: cacheDir)
        }
        try fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

        let tarPath = "\(cacheDir)/\(driverAssetName)"

        // Download using curl (available on all macOS)
        let curlCmd = "curl -fSL -o '\(tarPath)' '\(downloadURL)'"
        do {
            _ = try await shell(curlCmd)
        } catch {
            throw LassoError.commandFailed(
                "Failed to download prebuilt driver from \(downloadURL). "
                + "If you cloned the lasso repo, run 'lasso driver build' to build from source.",
                1
            )
        }

        // Extract — the tar contains a Products/ directory and driver-info.json
        _ = try await shell("tar -xzf '\(tarPath)' -C '\(cacheDir)'")
        try fm.removeItem(atPath: tarPath)

        // Verify extraction produced what we need
        guard fm.fileExists(atPath: productsDir) else {
            throw LassoError.commandFailed(
                "Downloaded driver archive did not contain expected Products/ directory",
                1
            )
        }
    }
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
