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
    /// Start a run with status "running" — returns run ID immediately.
    public var startRun: @Sendable (String, StartRunRequest) async throws -> RunResponse
    /// Complete a running run with screen results and images.
    public var completeRun: @Sendable (String, String, RunUpload) async throws -> RunResponse
    /// Append log lines to a running run.
    public var appendLog: @Sendable (String, String, String) async throws -> Void

    public init(
        me: @escaping @Sendable () async throws -> MeResponse,
        listBaselines: @escaping @Sendable (String, String) async throws -> [String],
        downloadBaseline: @escaping @Sendable (String, String, String) async throws -> Data,
        uploadBaseline: @escaping @Sendable (String, String, String, Data) async throws -> Void,
        deleteBaseline: @escaping @Sendable (String, String, String) async throws -> Void,
        promoteBaselines: @escaping @Sendable (String, String, String) async throws -> Void,
        createRun: @escaping @Sendable (String, RunUpload) async throws -> RunResponse,
        startRun: @escaping @Sendable (String, StartRunRequest) async throws -> RunResponse,
        completeRun: @escaping @Sendable (String, String, RunUpload) async throws -> RunResponse,
        appendLog: @escaping @Sendable (String, String, String) async throws -> Void
    ) {
        self.me = me
        self.listBaselines = listBaselines
        self.downloadBaseline = downloadBaseline
        self.uploadBaseline = uploadBaseline
        self.deleteBaseline = deleteBaseline
        self.promoteBaselines = promoteBaselines
        self.createRun = createRun
        self.startRun = startRun
        self.completeRun = completeRun
        self.appendLog = appendLog
    }
}

// MARK: - Convenience Init

extension RangeClient {
    public init(apiKey: String, baseURL: String) {
        let baseURL = URL(string: baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL)!
        let client = NetworkClient.authorized(apiKey: apiKey)

        self.init(
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
                let form = MultipartForm.build(from: upload)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
                request.httpBody = form.data
                let data = try await client.sendRequest(request)
                return try JSONDecoder().decode(RunResponse.self, from: data)
            },
            startRun: { project, startReq in
                let endpoint = RunEndpoints.create(project: project)
                let url = endpoint.url(relativeTo: baseURL)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = try JSONEncoder().encode([
                    "branch": startReq.branch,
                    "commit_sha": startReq.commitSHA ?? "",
                    "trigger": startReq.trigger,
                ])
                request.httpBody = body
                let data = try await client.sendRequest(request)
                return try JSONDecoder().decode(RunResponse.self, from: data)
            },
            completeRun: { project, runId, upload in
                let endpoint = RunEndpoints.complete(project: project, runId: runId)
                let url = endpoint.url(relativeTo: baseURL)
                let form = MultipartForm.build(from: upload)
                var request = URLRequest(url: url)
                request.httpMethod = "PATCH"
                request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
                request.httpBody = form.data
                let data = try await client.sendRequest(request)
                return try JSONDecoder().decode(RunResponse.self, from: data)
            },
            appendLog: { project, runId, lines in
                let endpoint = RunEndpoints.appendLog(project: project, runId: runId)
                let url = endpoint.url(relativeTo: baseURL)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["lines": lines])
                _ = try await client.sendRequest(request)
            }
        )
    }
}

// MARK: - Multipart Form Builder

/// Builds a standard multipart/form-data body matching Vapor's Content decoding expectations.
/// Form fields use `name="key"`, indexed arrays use `name="key[0]"`, files use `filename="name.png"`.
private struct MultipartForm {
    let data: Data
    let boundary: String
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    static func build(from upload: RunUpload) -> MultipartForm {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // Top-level form fields
        body.appendField(boundary: boundary, name: "branch", value: upload.branch)
        if let sha = upload.commitSHA {
            body.appendField(boundary: boundary, name: "commit_sha", value: sha)
        }
        body.appendField(boundary: boundary, name: "trigger", value: upload.trigger)
        if let duration = upload.duration {
            body.appendField(boundary: boundary, name: "duration", value: String(duration))
        }

        // Screens as indexed array of fields: screens[0][name], screens[0][status], etc.
        for (i, screen) in upload.screens.enumerated() {
            body.appendField(boundary: boundary, name: "screens[\(i)][name]", value: screen.name)
            body.appendField(boundary: boundary, name: "screens[\(i)][status]", value: screen.status)
            body.appendField(boundary: boundary, name: "screens[\(i)][pixel_threshold]", value: String(screen.pixelThreshold))
            body.appendField(boundary: boundary, name: "screens[\(i)][perceptual_threshold]", value: String(screen.perceptualThreshold))
            if let v = screen.pixelDiffPercent {
                body.appendField(boundary: boundary, name: "screens[\(i)][pixel_diff_percent]", value: String(v))
            }
            if let v = screen.perceptualDistance {
                body.appendField(boundary: boundary, name: "screens[\(i)][perceptual_distance]", value: String(v))
            }
            if let v = screen.message {
                body.appendField(boundary: boundary, name: "screens[\(i)][message]", value: v)
            }
        }

        // Capture files as indexed array: captures[0], captures[1], ...
        var captureIndex = 0
        for screen in upload.screens {
            if let captureData = screen.captureData {
                body.appendFile(boundary: boundary, name: "captures[\(captureIndex)]", filename: "\(screen.name).png", data: captureData)
                captureIndex += 1
            }
        }

        // Diff files as indexed array: diffs[0], diffs[1], ...
        var diffIndex = 0
        for screen in upload.screens {
            if let diffData = screen.diffData {
                body.appendFile(boundary: boundary, name: "diffs[\(diffIndex)]", filename: "\(screen.name)_diff.png", data: diffData)
                diffIndex += 1
            }
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return MultipartForm(data: body, boundary: boundary)
    }
}

private extension Data {
    mutating func appendField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append(value.data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendFile(boundary: String, name: String, filename: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
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
        createRun: { _, _ in throw LassoError.notAuthenticated },
        startRun: { _, _ in throw LassoError.notAuthenticated },
        completeRun: { _, _, _ in throw LassoError.notAuthenticated },
        appendLog: { _, _, _ in throw LassoError.notAuthenticated }
    )
}
