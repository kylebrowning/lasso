import Foundation

// MARK: - Capture Types

public struct ScreenCapture: Sendable, Codable {
    public let screenName: String
    public let path: String
    public let sizeBytes: Int
    public let timestamp: Date

    public init(screenName: String, path: String, sizeBytes: Int, timestamp: Date = Date()) {
        self.screenName = screenName
        self.path = path
        self.sizeBytes = sizeBytes
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case screenName = "screen_name"
        case path
        case sizeBytes = "size_bytes"
        case timestamp
    }
}

public struct CaptureResult: Sendable, Codable {
    public let screens: [ScreenCapture]
    public let directory: String
    public let duration: Double

    public init(screens: [ScreenCapture], directory: String, duration: Double) {
        self.screens = screens
        self.directory = directory
        self.duration = duration
    }
}

// MARK: - Diff Types

public enum DiffStatus: String, Sendable, Codable {
    case passed
    case failed
    case newScreen = "new_screen"
    case error
}

public struct ScreenDiff: Sendable, Codable {
    public let screenName: String
    public let status: DiffStatus
    public let pixelDiffPercent: Double?
    public let perceptualDistance: Double?
    public let pixelThreshold: Double
    public let perceptualThreshold: Double
    public let baselinePath: String?
    public let capturePath: String
    public let diffImagePath: String?
    public let message: String

    public init(
        screenName: String,
        status: DiffStatus,
        pixelDiffPercent: Double? = nil,
        perceptualDistance: Double? = nil,
        pixelThreshold: Double,
        perceptualThreshold: Double,
        baselinePath: String? = nil,
        capturePath: String,
        diffImagePath: String? = nil,
        message: String
    ) {
        self.screenName = screenName
        self.status = status
        self.pixelDiffPercent = pixelDiffPercent
        self.perceptualDistance = perceptualDistance
        self.pixelThreshold = pixelThreshold
        self.perceptualThreshold = perceptualThreshold
        self.baselinePath = baselinePath
        self.capturePath = capturePath
        self.diffImagePath = diffImagePath
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case screenName = "screen_name"
        case status
        case pixelDiffPercent = "pixel_diff_percent"
        case perceptualDistance = "perceptual_distance"
        case pixelThreshold = "pixel_threshold"
        case perceptualThreshold = "perceptual_threshold"
        case baselinePath = "baseline_path"
        case capturePath = "capture_path"
        case diffImagePath = "diff_image_path"
        case message
    }
}

public struct CompareResult: Sendable, Codable {
    public let screens: [ScreenDiff]
    public let passed: Bool
    public let duration: Double

    public init(screens: [ScreenDiff], passed: Bool, duration: Double) {
        self.screens = screens
        self.passed = passed
        self.duration = duration
    }
}

// MARK: - Approve Types

public struct ApproveResult: Sendable, Codable {
    public let approvedScreens: [String]
    public let baselineDirectory: String

    public init(approvedScreens: [String], baselineDirectory: String) {
        self.approvedScreens = approvedScreens
        self.baselineDirectory = baselineDirectory
    }

    enum CodingKeys: String, CodingKey {
        case approvedScreens = "approved_screens"
        case baselineDirectory = "baseline_directory"
    }
}
