import XCTest
@testable import LassoCore

final class LassoCoreTests: XCTestCase {

    // MARK: - SimulatorDevice

    func testSimulatorDeviceIsBooted() {
        let booted = SimulatorDevice(name: "iPhone 16", udid: "ABC-123", state: "Booted", runtime: "iOS-18-1", isAvailable: true)
        XCTAssertTrue(booted.isBooted)

        let shutdown = SimulatorDevice(name: "iPhone 16", udid: "ABC-123", state: "Shutdown", runtime: "iOS-18-1", isAvailable: true)
        XCTAssertFalse(shutdown.isBooted)
    }

    // MARK: - DoctorCheck

    func testDoctorCheckCreation() {
        let ok = DoctorCheck(name: "Xcode", status: .ok, message: "Installed", fix: nil)
        XCTAssertEqual(ok.status, .ok)
        XCTAssertNil(ok.fix)

        let warning = DoctorCheck(name: "A11y", status: .warning, message: "Missing", fix: "Grant access")
        XCTAssertEqual(warning.status, .warning)
        XCTAssertEqual(warning.fix, "Grant access")

        let fail = DoctorCheck(name: "Git", status: .error, message: "Not found", fix: "Install git")
        XCTAssertEqual(fail.status, .error)
    }

    // MARK: - LassoError

    func testLassoErrorDescriptions() {
        let cases: [LassoError] = [
            .simulatorNotRunning,
            .simulatorWindowNotFound,
            .elementNotFound("Button"),
            .buildFailed("exit 1"),
            .invalidImage,
            .notAuthenticated,
            .configNotFound,
            .commandFailed("test", 1),
            .networkError("timeout", 408),
            .baselineNotFound("Home"),
            .noCaptures(".lasso/captures"),
        ]

        for error in cases {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testNetworkErrorContainsStatusCode() {
        let error = LassoError.networkError("Not Found", 404)
        XCTAssertTrue(error.errorDescription!.contains("404"))
    }

    // MARK: - LassoConfig

    func testConfigDefaultValues() {
        let config = LassoConfig()
        XCTAssertNil(config.scheme)
        XCTAssertNil(config.simulator)
        XCTAssertEqual(config.diff.threshold, 0.02)
        XCTAssertEqual(config.diff.perceptualThreshold, 5.0)
        XCTAssertEqual(config.a11y.failOnNewViolations, true)
        XCTAssertEqual(config.a11y.rules, ["missing_label", "small_tap_target"])
        XCTAssertEqual(config.size.warnMb, 0.5)
        XCTAssertEqual(config.size.failMb, 2.0)
        XCTAssertEqual(config.ai.provider, "none")
    }

    func testConfigYAMLParsing() throws {
        let yaml = """
        scheme: MyApp
        simulator: iPhone 16
        bundle_id: com.example.myapp
        screens:
          - name: Home
            path: launch
          - name: Settings
            path:
              - tap: "Profile"
              - tap: "Settings"
        diff:
          threshold: 0.05
          perceptual_threshold: 10.0
        """

        let config = try YAMLDecoder().decode(LassoConfig.self, from: yaml)
        XCTAssertEqual(config.scheme, "MyApp")
        XCTAssertEqual(config.simulator, "iPhone 16")
        XCTAssertEqual(config.bundleId, "com.example.myapp")
        XCTAssertEqual(config.screens.count, 2)
        XCTAssertEqual(config.diff.threshold, 0.05)
        XCTAssertEqual(config.diff.perceptualThreshold, 10.0)
    }

    func testConfigDefaultsForMissingKeys() throws {
        let yaml = """
        screens:
          - name: Home
            path: launch
        """
        let config = try YAMLDecoder().decode(LassoConfig.self, from: yaml)
        XCTAssertNil(config.scheme)
        XCTAssertEqual(config.diff.threshold, 0.02)
        XCTAssertEqual(config.a11y.failOnNewViolations, true)
        XCTAssertEqual(config.size.warnMb, 0.5)
        XCTAssertEqual(config.ai.provider, "none")
    }

    func testScreenPathLaunch() throws {
        let yaml = """
        screens:
          - name: Home
            path: launch
        """
        let config = try YAMLDecoder().decode(LassoConfig.self, from: yaml)
        if case .launch = config.screens[0].path {
            // correct
        } else {
            XCTFail("Expected .launch path")
        }
    }

    func testScreenPathSteps() throws {
        let yaml = """
        screens:
          - name: Settings
            path:
              - tap: "Profile"
              - swipe: "up"
        """
        let config = try YAMLDecoder().decode(LassoConfig.self, from: yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps.count, 2)
            XCTAssertEqual(steps[0].tap, "Profile")
            XCTAssertEqual(steps[1].swipe, "up")
        } else {
            XCTFail("Expected .steps path")
        }
    }

    func testHasNavigationSteps() {
        let launchOnly: [LassoConfig.Screen] = [
            .init(name: "Home", path: .launch)
        ]
        XCTAssertFalse(launchOnly.hasNavigationSteps)

        let withSteps: [LassoConfig.Screen] = [
            .init(name: "Home", path: .launch),
            .init(name: "Settings", path: .steps([.init(tap: "Settings")])),
        ]
        XCTAssertTrue(withSteps.hasNavigationSteps)
    }

    // MARK: - LassoDefaults

    func testDefaultAPIBaseURL() {
        XCTAssertEqual(LassoDefaults.apiBaseURL, "https://lasso.build")
    }

    // MARK: - ImageDiffer

    func testImageDifferIdenticalImages() throws {
        let image = createTestPNG(width: 10, height: 10, color: (255, 0, 0))
        let output = try ImageDiffer.live.compare(image, image)
        XCTAssertEqual(output.pixelDiffPercent, 0.0)
        XCTAssertEqual(output.perceptualDistance, 0.0)
    }

    func testImageDifferDifferentImages() throws {
        let red = createTestPNG(width: 10, height: 10, color: (255, 0, 0))
        let blue = createTestPNG(width: 10, height: 10, color: (0, 0, 255))
        let output = try ImageDiffer.live.compare(red, blue)
        XCTAssertGreaterThan(output.pixelDiffPercent, 0.0)
        XCTAssertGreaterThan(output.perceptualDistance, 0.0)
        XCTAssertFalse(output.diffImageData.isEmpty)
    }

    func testImageDifferSizeMismatchThrows() {
        let small = createTestPNG(width: 10, height: 10, color: (255, 0, 0))
        let large = createTestPNG(width: 20, height: 20, color: (255, 0, 0))
        XCTAssertThrowsError(try ImageDiffer.live.compare(small, large)) { error in
            guard case LassoError.diffSizeMismatch = error else {
                XCTFail("Expected diffSizeMismatch, got \(error)")
                return
            }
        }
    }

    func testImageDifferInvalidDataThrows() {
        let garbage = Data("not an image".utf8)
        XCTAssertThrowsError(try ImageDiffer.live.compare(garbage, garbage))
    }

    func testImageDifferProducesDiffImage() throws {
        let red = createTestPNG(width: 10, height: 10, color: (255, 0, 0))
        let green = createTestPNG(width: 10, height: 10, color: (0, 255, 0))
        let output = try ImageDiffer.live.compare(red, green)
        // Diff image should be valid PNG data
        XCTAssertGreaterThan(output.diffImageData.count, 0)
        // PNG magic bytes
        let header = Array(output.diffImageData.prefix(4))
        XCTAssertEqual(header, [0x89, 0x50, 0x4E, 0x47]) // \x89PNG
    }

    // MARK: - Helpers

    private func createTestPNG(width: Int, height: Int, color: (UInt8, UInt8, UInt8)) -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = color.0
            pixels[i * 4 + 1] = color.1
            pixels[i * 4 + 2] = color.2
            pixels[i * 4 + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cgImage = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }
}

import Yams
