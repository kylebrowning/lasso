import XCTest
@testable import LassoRange

final class LassoRangeTests: XCTestCase {

    // MARK: - Endpoint URL Construction

    func testEndpointSimplePath() {
        let endpoint = Endpoint<EmptyBody, EmptyResponse>(path: "auth/me", method: .get)
        let url = endpoint.url(relativeTo: URL(string: "https://api.example.com")!)
        XCTAssertEqual(url.absoluteString, "https://api.example.com/auth/me")
    }

    func testEndpointWithQueryItems() {
        let endpoint = Endpoint<EmptyBody, EmptyResponse>(
            path: "runs",
            method: .get,
            queryItems: [URLQueryItem(name: "branch", value: "main")]
        )
        let url = endpoint.url(relativeTo: URL(string: "https://api.example.com")!)
        XCTAssertEqual(url.absoluteString, "https://api.example.com/runs?branch=main")
    }

    func testEndpointHTTPMethods() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
    }

    // MARK: - Baseline Endpoints

    func testBaselineListEndpoint() {
        let endpoint = BaselineEndpoints.list(project: "kylebrowning/lasso", branch: "main")
        let url = endpoint.url(relativeTo: URL(string: "https://api.example.com")!)
        // Project slug with "/" should be percent-encoded
        XCTAssertTrue(url.absoluteString.contains("kylebrowning%2Flasso"))
        XCTAssertTrue(url.absoluteString.contains("/baselines/"))
        XCTAssertTrue(url.absoluteString.contains("/main"))
    }

    func testBaselineDownloadEndpoint() {
        let endpoint = BaselineEndpoints.download(project: "owner/repo", branch: "feature/test", screen: "Home")
        let url = endpoint.url(relativeTo: URL(string: "https://api.example.com")!)
        XCTAssertTrue(url.absoluteString.contains("owner%2Frepo"))
        XCTAssertTrue(url.absoluteString.contains("feature%2Ftest"))
        XCTAssertTrue(url.absoluteString.contains("Home"))
    }

    func testBaselinePromoteEndpoint() {
        let request = PromoteBaselinesRequest(fromBranch: "feature/new")
        let endpoint = BaselineEndpoints.promote(project: "owner/repo", branch: "main", body: request)
        let url = endpoint.url(relativeTo: URL(string: "https://api.example.com")!)
        XCTAssertTrue(url.absoluteString.contains("/promote"))
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.body?.fromBranch, "feature/new")
    }

    // MARK: - Run Endpoints

    func testRunCreateEndpoint() {
        let endpoint = RunEndpoints.create(project: "kylebrowning/lasso")
        XCTAssertEqual(endpoint.method, .post)
        let url = endpoint.url(relativeTo: URL(string: "https://api.example.com")!)
        XCTAssertTrue(url.absoluteString.contains("/runs/"))
    }

    func testRunListEndpoint() {
        let endpoint = RunEndpoints.list(project: "kylebrowning/lasso")
        XCTAssertEqual(endpoint.method, .get)
    }

    func testRunDetailEndpoint() {
        let endpoint = RunEndpoints.detail(project: "owner/repo", runId: "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(endpoint.method, .get)
        let url = endpoint.url(relativeTo: URL(string: "https://api.example.com")!)
        XCTAssertTrue(url.absoluteString.contains("550e8400"))
    }

    // MARK: - Model Serialization

    func testPromoteBaselinesRequestEncoding() throws {
        let request = PromoteBaselinesRequest(fromBranch: "develop")
        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: String]
        XCTAssertEqual(dict["from_branch"], "develop")
    }

    func testRunResponseDecoding() throws {
        let json = """
        {
            "run_id": "abc-123",
            "status": "passed",
            "url": "https://lasso.build/?run=abc-123",
            "screen_count": 3,
            "passed_count": 3,
            "failed_count": 0,
            "new_count": 0
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RunResponse.self, from: json)
        XCTAssertEqual(response.runId, "abc-123")
        XCTAssertEqual(response.status, "passed")
        XCTAssertEqual(response.screenCount, 3)
        XCTAssertEqual(response.passedCount, 3)
        XCTAssertEqual(response.failedCount, 0)
        XCTAssertEqual(response.newCount, 0)
    }

    func testMeResponseDecoding() throws {
        let json = """
        {"email": "test@example.com", "api_key_prefix": "lasso_ab"}
        """.data(using: .utf8)!

        let me = try JSONDecoder().decode(MeResponse.self, from: json)
        XCTAssertEqual(me.email, "test@example.com")
        XCTAssertEqual(me.apiKeyPrefix, "lasso_ab")
    }

    func testRunListItemDecoding() throws {
        let json = """
        {
            "id": "uuid-1",
            "branch": "main",
            "commit_sha": "abc1234",
            "trigger": "ci",
            "status": "failed",
            "screen_count": 5,
            "passed_count": 3,
            "failed_count": 2,
            "new_count": 0,
            "duration": 12.5,
            "user_email": "test@example.com",
            "created_at": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(RunListItem.self, from: json)
        XCTAssertEqual(item.branch, "main")
        XCTAssertEqual(item.commitSha, "abc1234")
        XCTAssertEqual(item.trigger, "ci")
        XCTAssertEqual(item.failedCount, 2)
        XCTAssertEqual(item.duration, 12.5)
    }

    func testBaselineListResponseDecoding() throws {
        let json = """
        {"screens": ["Home", "Settings", "Profile"]}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(BaselineListResponse.self, from: json)
        XCTAssertEqual(response.screens, ["Home", "Settings", "Profile"])
    }

    // MARK: - RangeClient Failing

    func testFailingClientThrowsNotAuthenticated() async {
        do {
            _ = try await RangeClient.failing.me()
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
    }
}
