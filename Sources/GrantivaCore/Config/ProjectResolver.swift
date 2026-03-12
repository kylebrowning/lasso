import Foundation

// MARK: - ResolvedProject

public struct ResolvedProject: Sendable {
    public let scheme: String?
    public let project: String?
    public let workspace: String?
    public let bundleId: String?
    public let simulator: String
    public let screens: [GrantivaConfig.Screen]
    public let diff: GrantivaConfig.DiffConfig
    public let a11y: GrantivaConfig.A11yConfig
    public let size: GrantivaConfig.SizeConfig
    public let ai: GrantivaConfig.AIConfig

    public init(
        scheme: String? = nil,
        project: String? = nil,
        workspace: String? = nil,
        bundleId: String? = nil,
        simulator: String = "iPhone 16",
        screens: [GrantivaConfig.Screen] = [],
        diff: GrantivaConfig.DiffConfig = .init(),
        a11y: GrantivaConfig.A11yConfig = .init(),
        size: GrantivaConfig.SizeConfig = .init(),
        ai: GrantivaConfig.AIConfig = .init()
    ) {
        self.scheme = scheme
        self.project = project
        self.workspace = workspace
        self.bundleId = bundleId
        self.simulator = simulator
        self.screens = screens
        self.diff = diff
        self.a11y = a11y
        self.size = size
        self.ai = ai
    }
}

// MARK: - Resolve

extension ResolvedProject {
    /// Merges CLI flags → grantiva.yml → cache → live auto-detection.
    /// CLI flags and grantiva.yml always win. Cache/detection only fill in missing fields.
    ///
    /// When `skipBuild` is true, scheme is not required (no xcodebuild needed).
    /// When `appBundleId` is provided (derived from a binary), it's used as a fallback for bundle ID.
    public static func resolve(
        schemeFlag: String? = nil,
        simulatorFlag: String? = nil,
        bundleIdFlag: String? = nil,
        config: GrantivaConfig? = nil,
        detector: ProjectDetector = .live,
        skipBuild: Bool = false,
        appBundleId: String? = nil
    ) async throws -> ResolvedProject {
        // Start with what we have from flags and config
        let flagScheme = schemeFlag
        let configScheme = config?.scheme
        let flagSim = simulatorFlag
        let configSim = config?.simulator

        // If we already have a scheme from flags or config, we may not need detection
        var detected: DetectedProject?

        if !skipBuild {
            if flagScheme == nil && configScheme == nil {
                // Try cache first
                detected = ProjectDetector.loadCache()
                if detected == nil {
                    // Live detection
                    detected = try await detector.detect()
                    if let detected {
                        ProjectDetector.saveCache(detected)
                    }
                }
            } else if bundleIdFlag == nil && config?.bundleId == nil && appBundleId == nil {
                // We have scheme but no bundle ID — try cache/detection for bundle ID
                detected = ProjectDetector.loadCache()
                if detected == nil {
                    detected = try? await detector.detect()
                    if let detected {
                        ProjectDetector.saveCache(detected)
                    }
                }
            }
        }

        // Resolution: flags > config > detected
        let scheme = flagScheme ?? configScheme ?? detected?.scheme

        // Scheme is required unless we're skipping the build
        if scheme == nil && !skipBuild {
            throw GrantivaError.invalidArgument(
                "No scheme specified. Pass --scheme, set it in grantiva.yml, or use --app-file to provide a pre-built binary."
            )
        }

        // Bundle ID: CLI flag > config > binary Info.plist > detected
        let bundleId = bundleIdFlag ?? config?.bundleId ?? appBundleId ?? detected?.bundleId
        let workspace = config?.workspace ?? detected?.workspace
        let project = config?.project ?? detected?.project
        let simulator = flagSim ?? configSim ?? "iPhone 16"

        return ResolvedProject(
            scheme: scheme,
            project: project,
            workspace: workspace,
            bundleId: bundleId,
            simulator: simulator,
            screens: config?.screens ?? [],
            diff: config?.diff ?? .init(),
            a11y: config?.a11y ?? .init(),
            size: config?.size ?? .init(),
            ai: config?.ai ?? .init()
        )
    }
}
