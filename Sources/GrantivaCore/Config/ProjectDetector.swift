import Foundation

// MARK: - DetectedProject

public struct DetectedProject: Codable, Sendable {
    public var scheme: String
    public var project: String?
    public var workspace: String?
    public var bundleId: String?
    public var detectedAt: Date

    public init(
        scheme: String,
        project: String? = nil,
        workspace: String? = nil,
        bundleId: String? = nil,
        detectedAt: Date = Date()
    ) {
        self.scheme = scheme
        self.project = project
        self.workspace = workspace
        self.bundleId = bundleId
        self.detectedAt = detectedAt
    }
}

// MARK: - ProjectDetector

public struct ProjectDetector: Sendable {
    public var detect: @Sendable () async throws -> DetectedProject

    public init(detect: @escaping @Sendable () async throws -> DetectedProject) {
        self.detect = detect
    }
}

// MARK: - Live

extension ProjectDetector {
    public static let live = ProjectDetector {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        guard let contents = try? fm.contentsOfDirectory(atPath: cwd) else {
            throw GrantivaError.invalidArgument("Cannot read current directory")
        }

        // Find workspace or project
        let workspace = contents.first { $0.hasSuffix(".xcworkspace") && !$0.hasPrefix(".") }
        let project = contents.first { $0.hasSuffix(".xcodeproj") }

        // Run xcodebuild -list to get schemes
        var listCmd = "xcodebuild -list -json"
        if let workspace {
            listCmd += " -workspace \(workspace)"
        } else if let project {
            listCmd += " -project \(project)"
        } else {
            throw GrantivaError.invalidArgument("No .xcworkspace or .xcodeproj found in current directory")
        }

        let listOutput = try await shell(listCmd)
        guard let listData = listOutput.data(using: .utf8) else {
            throw GrantivaError.invalidArgument("Could not parse xcodebuild -list output")
        }

        let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
        let schemes: [String]
        if let ws = listJSON?["workspace"] as? [String: Any] {
            schemes = ws["schemes"] as? [String] ?? []
        } else if let proj = listJSON?["project"] as? [String: Any] {
            schemes = proj["schemes"] as? [String] ?? []
        } else {
            schemes = []
        }

        guard let scheme = schemes.first else {
            throw GrantivaError.invalidArgument("No schemes found in Xcode project")
        }

        // Get bundle ID from build settings
        var settingsCmd = "xcodebuild -scheme \(scheme) -showBuildSettings"
        if let workspace {
            settingsCmd += " -workspace \(workspace)"
        } else if let project {
            settingsCmd += " -project \(project)"
        }

        var bundleId: String?
        if let settingsOutput = try? await shell(settingsCmd) {
            for line in settingsOutput.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("PRODUCT_BUNDLE_IDENTIFIER = ") {
                    bundleId = String(trimmed.dropFirst("PRODUCT_BUNDLE_IDENTIFIER = ".count))
                    break
                }
            }
        }

        return DetectedProject(
            scheme: scheme,
            project: project,
            workspace: workspace,
            bundleId: bundleId
        )
    }
}

// MARK: - Cache

extension ProjectDetector {
    private static let cachePath = ".grantiva/config.json"

    public static func loadCache() -> DetectedProject? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cachePath),
              let data = fm.contents(atPath: cachePath),
              let cached = try? JSONDecoder().decode(DetectedProject.self, from: data) else {
            return nil
        }

        // Invalidate if xcodeproj is newer than cache
        let cacheURL = URL(fileURLWithPath: cachePath)
        guard let cacheDate = try? fm.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date else {
            return cached
        }

        let cwd = fm.currentDirectoryPath
        if let contents = try? fm.contentsOfDirectory(atPath: cwd) {
            for item in contents where item.hasSuffix(".xcodeproj") {
                let projPath = "\(cwd)/\(item)"
                if let projDate = try? fm.attributesOfItem(atPath: projPath)[.modificationDate] as? Date,
                   projDate > cacheDate {
                    return nil // Cache invalidated
                }
            }
        }

        return cached
    }

    public static func saveCache(_ project: DetectedProject) {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: ".grantiva")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if let data = try? JSONEncoder().encode(project) {
            fm.createFile(atPath: cachePath, contents: data)
        }
    }
}

// MARK: - Failing

extension ProjectDetector {
    public static let failing = ProjectDetector {
        throw GrantivaError.invalidArgument("ProjectDetector.failing")
    }
}
