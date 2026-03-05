import Foundation
import LassoCore

// MARK: - RangeClient

public struct RangeClient: Sendable {
    public var me: @Sendable () async throws -> MeResponse
    public var listBaselines: @Sendable (String, String) async throws -> [String]
    public var downloadBaseline: @Sendable (String, String, String) async throws -> Data
    public var uploadBaseline: @Sendable (String, String, String, Data) async throws -> Void
    public var deleteBaseline: @Sendable (String, String, String) async throws -> Void
    public var promoteBaselines: @Sendable (String, String, String) async throws -> Void
    public var createRun: @Sendable (String, RunUpload) async throws -> RunResponse

    public init(
        me: @escaping @Sendable () async throws -> MeResponse,
        listBaselines: @escaping @Sendable (String, String) async throws -> [String],
        downloadBaseline: @escaping @Sendable (String, String, String) async throws -> Data,
        uploadBaseline: @escaping @Sendable (String, String, String, Data) async throws -> Void,
        deleteBaseline: @escaping @Sendable (String, String, String) async throws -> Void,
        promoteBaselines: @escaping @Sendable (String, String, String) async throws -> Void,
        createRun: @escaping @Sendable (String, RunUpload) async throws -> RunResponse
    ) {
        self.me = me
        self.listBaselines = listBaselines
        self.downloadBaseline = downloadBaseline
        self.uploadBaseline = uploadBaseline
        self.deleteBaseline = deleteBaseline
        self.promoteBaselines = promoteBaselines
        self.createRun = createRun
    }
}

// MARK: - Live

extension RangeClient {
    public static func live(apiKey: String, baseURL: String) -> RangeClient {
        let baseURL = URL(string: baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL)!
        let client = NetworkClient.authorized(apiKey: apiKey)

        return RangeClient(
            me: {
                try await client.execute(AuthEndpoints.me(), baseURL: baseURL)
            },
            listBaselines: { project, branch in
                let response: BaselineListResponse = try await client.execute(
                    BaselineEndpoints.list(project: project, branch: branch),
                    baseURL: baseURL
                )
                return response.screens
            },
            downloadBaseline: { project, branch, screen in
                try await client.download(
                    BaselineEndpoints.download(project: project, branch: branch, screen: screen),
                    baseURL: baseURL
                )
            },
            uploadBaseline: { project, branch, screen, imageData in
                try await client.upload(
                    BaselineEndpoints.upload(project: project, branch: branch, screen: screen),
                    baseURL: baseURL,
                    data: imageData,
                    contentType: "image/png"
                )
            },
            deleteBaseline: { project, branch, screen in
                _ = try await client.execute(
                    BaselineEndpoints.delete(project: project, branch: branch, screen: screen),
                    baseURL: baseURL
                )
            },
            promoteBaselines: { project, targetBranch, fromBranch in
                let request = PromoteBaselinesRequest(fromBranch: fromBranch)
                _ = try await client.execute(
                    BaselineEndpoints.promote(project: project, branch: targetBranch, body: request),
                    baseURL: baseURL
                )
            },
            createRun: { project, upload in
                let endpoint = RunEndpoints.create(project: project)
                let url = endpoint.url(relativeTo: baseURL)
                let multipart = MultipartBody.build(from: upload)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
                request.httpBody = multipart.data
                let data = try await client.sendRequest(request)
                return try JSONDecoder().decode(RunResponse.self, from: data)
            }
        )
    }
}

// MARK: - Multipart Body Builder

private struct MultipartBody {
    let data: Data
    let boundary: String
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    static func build(from upload: RunUpload) -> MultipartBody {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // Metadata part
        let metadata = RunMetadataDTO(
            branch: upload.branch,
            commitSha: upload.commitSHA,
            trigger: upload.trigger,
            duration: upload.duration,
            screens: upload.screens.map { s in
                RunMetadataDTO.ScreenDTO(
                    name: s.name,
                    status: s.status,
                    pixelDiffPercent: s.pixelDiffPercent,
                    perceptualDistance: s.perceptualDistance,
                    pixelThreshold: s.pixelThreshold,
                    perceptualThreshold: s.perceptualThreshold,
                    message: s.message
                )
            }
        )

        let metadataJSON = try! JSONEncoder().encode(metadata)
        body.appendMultipart(boundary: boundary, name: "metadata", contentType: "application/json", data: metadataJSON)

        // Capture + diff image parts
        for screen in upload.screens {
            if let captureData = screen.captureData {
                body.appendMultipart(
                    boundary: boundary, name: "capture_\(screen.name)",
                    filename: "\(screen.name).png", contentType: "image/png", data: captureData
                )
            }
            if let diffData = screen.diffData {
                body.appendMultipart(
                    boundary: boundary, name: "diff_\(screen.name)",
                    filename: "\(screen.name)_diff.png", contentType: "image/png", data: diffData
                )
            }
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return MultipartBody(data: body, boundary: boundary)
    }
}

/// Internal DTO for multipart metadata — maps to backend's expected JSON shape.
private struct RunMetadataDTO: Encodable {
    let branch: String
    let commitSha: String?
    let trigger: String
    let duration: Double?
    let screens: [ScreenDTO]

    enum CodingKeys: String, CodingKey {
        case branch
        case commitSha = "commit_sha"
        case trigger, duration, screens
    }

    struct ScreenDTO: Encodable {
        let name: String
        let status: String
        let pixelDiffPercent: Double?
        let perceptualDistance: Double?
        let pixelThreshold: Double
        let perceptualThreshold: Double
        let message: String?

        enum CodingKeys: String, CodingKey {
            case name, status, message
            case pixelDiffPercent = "pixel_diff_percent"
            case perceptualDistance = "perceptual_distance"
            case pixelThreshold = "pixel_threshold"
            case perceptualThreshold = "perceptual_threshold"
        }
    }
}

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String? = nil, contentType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        if let filename {
            append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        } else {
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n".data(using: .utf8)!)
        }
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}

// MARK: - BaselineStore Adapter

extension RangeClient {
    public func asBaselineStore(project: String, branch: String, baseURL: String = LassoDefaults.apiBaseURL) -> BaselineStore {
        return BaselineStore(
            save: { screen, data in
                try await self.uploadBaseline(project, branch, screen, data)
                return "\(baseURL)/baselines/\(project)/\(branch)/\(screen)"
            },
            load: { screen in
                try? await self.downloadBaseline(project, branch, screen)
            },
            list: {
                try await self.listBaselines(project, branch)
            },
            delete: { screen in
                try await self.deleteBaseline(project, branch, screen)
            },
            baselineDirectory: { "\(baseURL)/baselines/\(project)/\(branch)" }
        )
    }
}

// MARK: - Failing

extension RangeClient {
    public static let failing = RangeClient(
        me: { throw LassoError.notAuthenticated },
        listBaselines: { _, _ in throw LassoError.notAuthenticated },
        downloadBaseline: { _, _, _ in throw LassoError.notAuthenticated },
        uploadBaseline: { _, _, _, _ in throw LassoError.notAuthenticated },
        deleteBaseline: { _, _, _ in throw LassoError.notAuthenticated },
        promoteBaselines: { _, _, _ in throw LassoError.notAuthenticated },
        createRun: { _, _ in throw LassoError.notAuthenticated }
    )
}
