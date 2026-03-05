import XCTest
@testable import LassoMCP

final class LassoMCPTests: XCTestCase {
    func testMCPServerInitializes() {
        let server = MCPServer()
        XCTAssertNotNil(server)
    }
}
