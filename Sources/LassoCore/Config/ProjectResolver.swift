import Foundation

// MARK: - ResolvedProject

public struct ResolvedProject: Sendable {
    public let scheme: String
    public let project: String?
    public let workspace: String?
    public let bundleId: String?
    public let simulator: String
    public let screens: [LassoConfig.Screen]
    public let diff: LassoConfig.DiffConfig
    public let a11y: LassoConfig.A11yConfig
    public let size: LassoConfig.SizeConfig
    public let ai: LassoConfig.AIConfig

    public init(
        scheme: String,
        project: String? = nil,
        workspace: String? = nil,
        bundleId: String? = nil,
        simulator: String = "iPhone 16",
        screens: [LassoConfig.Screen] = [],
        diff: LassoConfig.DiffConfig = .init(),
        a11y: LassoConfig.A11yConfig = .init(),
        size: LassoConfig.SizeConfig = .init(),
        ai: LassoConfig.AIConfig = .init()
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
    /// Merges CLI flags → lasso.yml → cache → live auto-detection.
    /// CLI flags and lasso.yml always win. Cache/detection only fill in missing fields.
    public static func resolve(
        schemeFlag: String? = nil,
        simulatorFlag: String? = nil,
        bundleIdFlag: String? = nil,
        config: LassoConfig? = nil,
        detector: ProjectDetector = .live
    ) async throws -> ResolvedProject {
        // Start with what we have from flags and config
        let flagScheme = schemeFlag
        let configScheme = config?.scheme
        let flagSim = simulatorFlag
        let configSim = config?.simulator

        // If we already have a scheme from flags or config, we may not need detection
        var detected: DetectedProject?
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
        } else if bundleIdFlag == nil && config?.bundleId == nil {
            // We have scheme but no bundle ID — try cache/detection for bundle ID
            detected = ProjectDetector.loadCache()
            if detected == nil {
                detected = try? await detector.detect()
                if let detected {
                    ProjectDetector.saveCache(detected)
                }
            }
        }

        // Resolution: flags > config > detected
        let scheme = flagScheme ?? configScheme ?? detected?.scheme
        guard let scheme else {
            throw LassoError.invalidArgument(
                "No scheme specified. Pass --scheme, set it in lasso.yml, or run from a directory with an Xcode project."
            )
        }

        let bundleId = bundleIdFlag ?? config?.bundleId ?? detected?.bundleId
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
