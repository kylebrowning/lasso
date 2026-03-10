import Foundation

// MARK: - Auth

public struct RegisterResponse: Codable, Sendable {
    public let apiKey: String
    public let email: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case email
    }

    public init(apiKey: String, email: String) {
        self.apiKey = apiKey
        self.email = email
    }
}

public struct MeResponse: Codable, Sendable {
    public let email: String
    public let apiKeyPrefix: String

    enum CodingKeys: String, CodingKey {
        case email
        case apiKeyPrefix = "api_key_prefix"
    }

    public init(email: String, apiKeyPrefix: String) {
        self.email = email
        self.apiKeyPrefix = apiKeyPrefix
    }
}

// MARK: - Baseline Requests

public struct PromoteBaselinesRequest: Encodable, Sendable {
    public let fromBranch: String

    enum CodingKeys: String, CodingKey {
        case fromBranch = "from_branch"
    }

    public init(fromBranch: String) {
        self.fromBranch = fromBranch
    }
}

// MARK: - Baseline Responses

public struct BaselineListResponse: Codable, Sendable {
    public let screens: [String]

    public init(screens: [String]) {
        self.screens = screens
    }
}

// MARK: - Runs

public struct RunStepUpload: Sendable, Codable {
    public let action: String
    public let status: String
    public let duration: Double
    public let message: String?

    public init(action: String, status: String, duration: Double, message: String? = nil) {
        self.action = action
        self.status = status
        self.duration = duration
        self.message = message
    }
}

public struct RunScreenUpload: Sendable {
    public let name: String
    public let status: String
    public let pixelDiffPercent: Double?
    public let perceptualDistance: Double?
    public let pixelThreshold: Double
    public let perceptualThreshold: Double
    public let message: String?
    public let captureData: Data?
    public let diffData: Data?
    public let steps: [RunStepUpload]

    public init(
        name: String,
        status: String,
        pixelDiffPercent: Double? = nil,
        perceptualDistance: Double? = nil,
        pixelThreshold: Double,
        perceptualThreshold: Double,
        message: String? = nil,
        captureData: Data? = nil,
        diffData: Data? = nil,
        steps: [RunStepUpload] = []
    ) {
        self.name = name
        self.status = status
        self.pixelDiffPercent = pixelDiffPercent
        self.perceptualDistance = perceptualDistance
        self.pixelThreshold = pixelThreshold
        self.perceptualThreshold = perceptualThreshold
        self.message = message
        self.captureData = captureData
        self.diffData = diffData
        self.steps = steps
    }
}

public struct RunUpload: Sendable {
    public let branch: String
    public let commitSHA: String?
    public let trigger: String
    public let duration: Double?
    public let screens: [RunScreenUpload]

    public init(
        branch: String,
        commitSHA: String? = nil,
        trigger: String,
        duration: Double?,
        screens: [RunScreenUpload]
    ) {
        self.branch = branch
        self.commitSHA = commitSHA
        self.trigger = trigger
        self.duration = duration
        self.screens = screens
    }
}

public struct StartRunRequest: Sendable {
    public let branch: String
    public let commitSHA: String?
    public let trigger: String

    public init(branch: String, commitSHA: String?, trigger: String) {
        self.branch = branch
        self.commitSHA = commitSHA
        self.trigger = trigger
    }
}

public struct RunResponse: Codable, Sendable {
    public let runId: String
    public let status: String
    public let url: String
    public let screenCount: Int
    public let passedCount: Int
    public let failedCount: Int
    public let newCount: Int

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case url
        case screenCount = "screen_count"
        case passedCount = "passed_count"
        case failedCount = "failed_count"
        case newCount = "new_count"
    }

    public init(
        runId: String,
        status: String,
        url: String,
        screenCount: Int,
        passedCount: Int,
        failedCount: Int,
        newCount: Int
    ) {
        self.runId = runId
        self.status = status
        self.url = url
        self.screenCount = screenCount
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.newCount = newCount
    }
}

public struct RunListItem: Codable, Sendable {
    public let id: String
    public let branch: String
    public let commitSha: String?
    public let trigger: String
    public let status: String
    public let screenCount: Int
    public let passedCount: Int
    public let failedCount: Int
    public let newCount: Int
    public let duration: Double?
    public let userEmail: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, branch, trigger, status, duration
        case commitSha = "commit_sha"
        case screenCount = "screen_count"
        case passedCount = "passed_count"
        case failedCount = "failed_count"
        case newCount = "new_count"
        case userEmail = "user_email"
        case createdAt = "created_at"
    }

    public init(
        id: String, branch: String, commitSha: String?, trigger: String,
        status: String, screenCount: Int, passedCount: Int, failedCount: Int,
        newCount: Int, duration: Double?, userEmail: String?, createdAt: String?
    ) {
        self.id = id
        self.branch = branch
        self.commitSha = commitSha
        self.trigger = trigger
        self.status = status
        self.screenCount = screenCount
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.newCount = newCount
        self.duration = duration
        self.userEmail = userEmail
        self.createdAt = createdAt
    }
}

public struct RunListResponse: Codable, Sendable {
    public let runs: [RunListItem]

    public init(runs: [RunListItem]) {
        self.runs = runs
    }
}

public struct RunScreenResultResponse: Codable, Sendable {
    public let id: String
    public let screenName: String
    public let status: String
    public let pixelDiffPercent: Double?
    public let perceptualDistance: Double?
    public let pixelThreshold: Double
    public let perceptualThreshold: Double
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case id
        case screenName = "screen_name"
        case status
        case pixelDiffPercent = "pixel_diff_percent"
        case perceptualDistance = "perceptual_distance"
        case pixelThreshold = "pixel_threshold"
        case perceptualThreshold = "perceptual_threshold"
        case message
    }

    public init(
        id: String, screenName: String, status: String,
        pixelDiffPercent: Double?, perceptualDistance: Double?,
        pixelThreshold: Double, perceptualThreshold: Double, message: String?
    ) {
        self.id = id
        self.screenName = screenName
        self.status = status
        self.pixelDiffPercent = pixelDiffPercent
        self.perceptualDistance = perceptualDistance
        self.pixelThreshold = pixelThreshold
        self.perceptualThreshold = perceptualThreshold
        self.message = message
    }
}

public struct RunDetailResponse: Codable, Sendable {
    public let run: RunListItem
    public let screens: [RunScreenResultResponse]

    public init(run: RunListItem, screens: [RunScreenResultResponse]) {
        self.run = run
        self.screens = screens
    }
}
