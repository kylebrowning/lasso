import Foundation

// MARK: - Path Encoding

private func encodedSegment(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowedWithoutSlash) ?? value
}

private extension CharacterSet {
    static let urlPathAllowedWithoutSlash: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove("/")
        return set
    }()
}

// MARK: - Auth Endpoints

enum AuthEndpoints {
    static func me() -> Endpoint<EmptyBody, MeResponse> {
        Endpoint(path: "auth/me", method: .get)
    }
}

// MARK: - Baseline Endpoints

enum BaselineEndpoints {
    static func list(project: String, branch: String) -> Endpoint<EmptyBody, BaselineListResponse> {
        Endpoint(
            path: "baselines/\(encodedSegment(project))/\(encodedSegment(branch))",
            method: .get
        )
    }

    static func download(project: String, branch: String, screen: String) -> Endpoint<EmptyBody, EmptyResponse> {
        Endpoint(
            path: "baselines/\(encodedSegment(project))/\(encodedSegment(branch))/\(encodedSegment(screen))",
            method: .get
        )
    }

    static func upload(project: String, branch: String, screen: String) -> Endpoint<EmptyBody, EmptyResponse> {
        Endpoint(
            path: "baselines/\(encodedSegment(project))/\(encodedSegment(branch))/\(encodedSegment(screen))",
            method: .post
        )
    }

    static func delete(project: String, branch: String, screen: String) -> Endpoint<EmptyBody, EmptyResponse> {
        Endpoint(
            path: "baselines/\(encodedSegment(project))/\(encodedSegment(branch))/\(encodedSegment(screen))",
            method: .delete
        )
    }

    static func promote(project: String, branch: String, body: PromoteBaselinesRequest) -> Endpoint<PromoteBaselinesRequest, EmptyResponse> {
        Endpoint(
            path: "baselines/\(encodedSegment(project))/\(encodedSegment(branch))/promote",
            method: .post,
            body: body
        )
    }
}

// MARK: - Run Endpoints

enum RunEndpoints {
    static func create(project: String) -> Endpoint<EmptyBody, RunResponse> {
        Endpoint(
            path: "runs/\(encodedSegment(project))",
            method: .post
        )
    }

    static func list(project: String) -> Endpoint<EmptyBody, RunListResponse> {
        Endpoint(
            path: "runs/\(encodedSegment(project))",
            method: .get
        )
    }

    static func detail(project: String, runId: String) -> Endpoint<EmptyBody, RunDetailResponse> {
        Endpoint(
            path: "runs/\(encodedSegment(project))/\(runId)",
            method: .get
        )
    }
}
