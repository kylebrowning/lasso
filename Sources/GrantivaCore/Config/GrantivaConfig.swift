import Foundation
import Yams

public struct GrantivaConfig: Sendable, Codable {
    public var scheme: String?
    public var workspace: String?
    public var project: String?
    public var simulator: String?
    public var bundleId: String?
    public var buildSettings: [String]?
    public var screens: [Screen]
    /// Paths to external Maestro YAML flow files to run in addition to `screens`.
    public var flows: [String]
    public var diff: DiffConfig
    public var a11y: A11yConfig
    public var size: SizeConfig
    public var ai: AIConfig

    public struct Screen: Sendable, Codable {
        public var name: String
        public var path: ScreenPath

        public struct Step: Sendable, Codable {
            public var tap: String?
            public var swipe: String?
            public var type: String?
            public var wait: Double?
            public var assertVisible: String?
            public var assertNotVisible: String?
            public var runFlow: String?

            public init(
                tap: String? = nil, swipe: String? = nil, type: String? = nil,
                wait: Double? = nil, assertVisible: String? = nil,
                assertNotVisible: String? = nil, runFlow: String? = nil
            ) {
                self.tap = tap
                self.swipe = swipe
                self.type = type
                self.wait = wait
                self.assertVisible = assertVisible
                self.assertNotVisible = assertNotVisible
                self.runFlow = runFlow
            }

            enum CodingKeys: String, CodingKey {
                case tap, swipe, type, wait
                case assertVisible = "assert_visible"
                case assertNotVisible = "assert_not_visible"
                case runFlow = "run_flow"
            }
        }

        public init(name: String, path: ScreenPath) {
            self.name = name
            self.path = path
        }
    }

    public enum ScreenPath: Sendable {
        case launch
        case steps([Screen.Step])
    }

    public struct DiffConfig: Sendable, Codable {
        public var threshold: Double
        public var perceptualThreshold: Double

        public init(threshold: Double = 0.02, perceptualThreshold: Double = 5.0) {
            self.threshold = threshold
            self.perceptualThreshold = perceptualThreshold
        }

        enum CodingKeys: String, CodingKey {
            case threshold
            case perceptualThreshold = "perceptual_threshold"
        }
    }

    public struct A11yConfig: Sendable, Codable {
        public var failOnNewViolations: Bool
        public var rules: [String]

        public init(failOnNewViolations: Bool = true, rules: [String] = ["missing_label", "small_tap_target"]) {
            self.failOnNewViolations = failOnNewViolations
            self.rules = rules
        }

        enum CodingKeys: String, CodingKey {
            case failOnNewViolations = "fail_on_new_violations"
            case rules
        }
    }

    public struct SizeConfig: Sendable, Codable {
        public var warnMb: Double
        public var failMb: Double

        public init(warnMb: Double = 0.5, failMb: Double = 2.0) {
            self.warnMb = warnMb
            self.failMb = failMb
        }

        enum CodingKeys: String, CodingKey {
            case warnMb = "warn_mb"
            case failMb = "fail_mb"
        }
    }

    public struct AIConfig: Sendable, Codable {
        public var provider: String

        public init(provider: String = "none") {
            self.provider = provider
        }
    }

    enum CodingKeys: String, CodingKey {
        case scheme, workspace, project, simulator
        case bundleId = "bundle_id"
        case buildSettings = "build_settings"
        case screens, flows, diff, a11y, size, ai
    }

    public init(
        scheme: String? = nil,
        workspace: String? = nil,
        project: String? = nil,
        simulator: String? = nil,
        bundleId: String? = nil,
        buildSettings: [String]? = nil,
        screens: [Screen] = [],
        flows: [String] = [],
        diff: DiffConfig = .init(),
        a11y: A11yConfig = .init(),
        size: SizeConfig = .init(),
        ai: AIConfig = .init()
    ) {
        self.scheme = scheme
        self.workspace = workspace
        self.project = project
        self.simulator = simulator
        self.bundleId = bundleId
        self.buildSettings = buildSettings
        self.screens = screens
        self.flows = flows
        self.diff = diff
        self.a11y = a11y
        self.size = size
        self.ai = ai
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        simulator = try container.decodeIfPresent(String.self, forKey: .simulator)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        buildSettings = try container.decodeIfPresent([String].self, forKey: .buildSettings)
        screens = try container.decodeIfPresent([Screen].self, forKey: .screens) ?? []
        flows = try container.decodeIfPresent([String].self, forKey: .flows) ?? []
        diff = try container.decodeIfPresent(DiffConfig.self, forKey: .diff) ?? .init()
        a11y = try container.decodeIfPresent(A11yConfig.self, forKey: .a11y) ?? .init()
        size = try container.decodeIfPresent(SizeConfig.self, forKey: .size) ?? .init()
        ai = try container.decodeIfPresent(AIConfig.self, forKey: .ai) ?? .init()
    }

    public static func load(from directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> GrantivaConfig {
        let fm = FileManager.default

        // 1. Try grantiva.yml (Grantiva or Maestro format)
        let configURL = directory.appendingPathComponent("grantiva.yml")
        if fm.fileExists(atPath: configURL.path) {
            let contents = try String(contentsOf: configURL, encoding: .utf8)

            // Auto-detect Maestro format
            if MaestroFlowParser.isMaestroFormat(contents) {
                return try MaestroFlowParser.parse(contents)
            }

            let decoder = YAMLDecoder()
            return try decoder.decode(GrantivaConfig.self, from: contents)
        }

        // 2. Try .maestro/ directory (Maestro flow files)
        let maestroDir = directory.appendingPathComponent(".maestro")
        if fm.fileExists(atPath: maestroDir.path) {
            return try MaestroFlowParser.loadDirectory(maestroDir)
        }

        throw GrantivaError.configNotFound
    }
}

// MARK: - Screen Helpers

extension Array where Element == GrantivaConfig.Screen {
    /// True if any screen requires navigation steps (taps/swipes) to reach.
    public var hasNavigationSteps: Bool {
        contains { screen in
            if case .steps(let steps) = screen.path, !steps.isEmpty {
                return true
            }
            return false
        }
    }
}

// MARK: - ScreenPath Codable

extension GrantivaConfig.ScreenPath: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self), str == "launch" {
            self = .launch
        } else {
            let steps = try container.decode([GrantivaConfig.Screen.Step].self)
            self = .steps(steps)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .launch:
            try container.encode("launch")
        case .steps(let steps):
            try container.encode(steps)
        }
    }
}
