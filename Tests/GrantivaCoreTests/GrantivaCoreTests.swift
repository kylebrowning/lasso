import XCTest
@testable import GrantivaCore

final class GrantivaCoreTests: XCTestCase {

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

    // MARK: - GrantivaError

    func testGrantivaErrorDescriptions() {
        let cases: [GrantivaError] = [
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
            .noCaptures(".grantiva/captures"),
        ]

        for error in cases {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testNetworkErrorContainsStatusCode() {
        let error = GrantivaError.networkError("Not Found", 404)
        XCTAssertTrue(error.errorDescription!.contains("404"))
    }

    // MARK: - GrantivaConfig

    func testConfigDefaultValues() {
        let config = GrantivaConfig()
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

        let config = try YAMLDecoder().decode(GrantivaConfig.self, from: yaml)
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
        let config = try YAMLDecoder().decode(GrantivaConfig.self, from: yaml)
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
        let config = try YAMLDecoder().decode(GrantivaConfig.self, from: yaml)
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
        let config = try YAMLDecoder().decode(GrantivaConfig.self, from: yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps.count, 2)
            XCTAssertEqual(steps[0].tap, "Profile")
            XCTAssertEqual(steps[1].swipe, "up")
        } else {
            XCTFail("Expected .steps path")
        }
    }

    func testHasNavigationSteps() {
        let launchOnly: [GrantivaConfig.Screen] = [
            .init(name: "Home", path: .launch)
        ]
        XCTAssertFalse(launchOnly.hasNavigationSteps)

        let withSteps: [GrantivaConfig.Screen] = [
            .init(name: "Home", path: .launch),
            .init(name: "Settings", path: .steps([.init(tap: "Settings")])),
        ]
        XCTAssertTrue(withSteps.hasNavigationSteps)
    }

    // MARK: - GrantivaDefaults

    func testDefaultAPIBaseURL() {
        XCTAssertEqual(GrantivaDefaults.apiBaseURL, "https://api.grantiva.io")
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
            guard case GrantivaError.diffSizeMismatch = error else {
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

// MARK: - MaestroFlowParser Tests

final class MaestroFlowParserTests: XCTestCase {

    func testIsMaestroFormatDetection() {
        XCTAssertTrue(MaestroFlowParser.isMaestroFormat("appId: com.example.app\n---\n- launchApp"))
        XCTAssertTrue(MaestroFlowParser.isMaestroFormat("- tapOn: \"Login\""))
        XCTAssertTrue(MaestroFlowParser.isMaestroFormat("- launchApp"))
        XCTAssertTrue(MaestroFlowParser.isMaestroFormat("- inputText: \"hello\""))
        XCTAssertTrue(MaestroFlowParser.isMaestroFormat("- assertVisible: \"Welcome\""))
        XCTAssertTrue(MaestroFlowParser.isMaestroFormat("- takeScreenshot: \"Home\""))

        // Grantiva format should NOT be detected as Maestro
        XCTAssertFalse(MaestroFlowParser.isMaestroFormat("scheme: MyApp\nscreens:\n  - name: Home\n    path: launch"))
        XCTAssertFalse(MaestroFlowParser.isMaestroFormat("screens:\n  - name: Home"))
    }

    func testParseFullMaestroFlow() throws {
        let yaml = """
        appId: com.example.myapp
        name: Login Flow
        ---
        - launchApp
        - tapOn: "Sign In"
        - inputText: "user@example.com"
        - takeScreenshot: "Login"
        - tapOn: "Submit"
        - assertVisible: "Welcome"
        - takeScreenshot: "Welcome"
        """

        let config = try MaestroFlowParser.parse(yaml)
        XCTAssertEqual(config.bundleId, "com.example.myapp")
        XCTAssertEqual(config.screens.count, 2)

        // First screen: "Login" — has tap + type steps
        XCTAssertEqual(config.screens[0].name, "Login")
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps.count, 2)
            XCTAssertEqual(steps[0].tap, "Sign In")
            XCTAssertEqual(steps[1].type, "user@example.com")
        } else {
            XCTFail("Expected steps, got launch")
        }

        // Second screen: "Welcome" — has tap + assert steps
        XCTAssertEqual(config.screens[1].name, "Welcome")
        if case .steps(let steps) = config.screens[1].path {
            XCTAssertEqual(steps.count, 2)
            XCTAssertEqual(steps[0].tap, "Submit")
            XCTAssertEqual(steps[1].assertVisible, "Welcome")
        } else {
            XCTFail("Expected steps, got launch")
        }
    }

    func testParseMaestroFlowWithoutConfig() throws {
        let yaml = """
        - tapOn: "Login"
        - inputText: "test"
        - takeScreenshot: "Result"
        """

        let config = try MaestroFlowParser.parse(yaml)
        XCTAssertNil(config.bundleId)
        XCTAssertEqual(config.screens.count, 1)
        XCTAssertEqual(config.screens[0].name, "Result")
    }

    func testParseMaestroFlowNoScreenshots() throws {
        let yaml = """
        appId: com.example.app
        ---
        - launchApp
        - tapOn: "Button"
        - assertVisible: "Done"
        """

        let config = try MaestroFlowParser.parse(yaml)
        // Remaining steps after no screenshot → one screen
        XCTAssertEqual(config.screens.count, 1)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps.count, 2)
            XCTAssertEqual(steps[0].tap, "Button")
            XCTAssertEqual(steps[1].assertVisible, "Done")
        } else {
            XCTFail("Expected steps")
        }
    }

    func testParseMaestroLaunchOnly() throws {
        let yaml = """
        appId: com.example.app
        ---
        - launchApp
        """

        let config = try MaestroFlowParser.parse(yaml)
        XCTAssertEqual(config.screens.count, 1)
        if case .launch = config.screens[0].path {
            // correct
        } else {
            XCTFail("Expected launch path")
        }
    }

    func testParseScrollInversion() throws {
        let yaml = """
        - scroll:
            direction: down
        - takeScreenshot: "Scrolled"
        """

        let config = try MaestroFlowParser.parse(yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps[0].swipe, "up") // scroll down = swipe up
        } else {
            XCTFail("Expected steps")
        }
    }

    func testParseBareScrollCommand() throws {
        let yaml = """
        - scroll
        - takeScreenshot: "After Scroll"
        """

        let config = try MaestroFlowParser.parse(yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps[0].swipe, "up") // default scroll = down = swipe up
        } else {
            XCTFail("Expected steps")
        }
    }

    func testParseSwipeFromCoordinates() throws {
        let yaml = """
        - swipe:
            start: {x: 200, y: 500}
            end: {x: 200, y: 100}
        - takeScreenshot: "Swiped"
        """

        let config = try MaestroFlowParser.parse(yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps[0].swipe, "up") // y decreases = swipe up
        } else {
            XCTFail("Expected steps")
        }
    }

    func testParseRunFlowVariants() throws {
        let yaml = """
        - runFlow: login.yaml
        - runFlow:
            file: checkout.yaml
        - takeScreenshot: "After Flows"
        """

        let config = try MaestroFlowParser.parse(yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps.count, 2)
            XCTAssertEqual(steps[0].runFlow, "login.yaml")
            XCTAssertEqual(steps[1].runFlow, "checkout.yaml")
        } else {
            XCTFail("Expected steps")
        }
    }

    func testParseTapSelectorVariants() throws {
        let yaml = """
        - tapOn: "Button Text"
        - tapOn:
            text: "Other Button"
        - tapOn:
            id: "button_id"
        - takeScreenshot: "Tapped"
        """

        let config = try MaestroFlowParser.parse(yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps.count, 3)
            XCTAssertEqual(steps[0].tap, "Button Text")
            XCTAssertEqual(steps[1].tap, "Other Button")
            XCTAssertEqual(steps[2].tap, "button_id")
        } else {
            XCTFail("Expected steps")
        }
    }

    func testParseWaitForAnimationToEnd() throws {
        let yaml = """
        - waitForAnimationToEnd:
            timeout: 3000
        - takeScreenshot: "Settled"
        """

        let config = try MaestroFlowParser.parse(yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps[0].wait, 3.0) // 3000ms → 3.0s
        } else {
            XCTFail("Expected steps")
        }
    }

    func testParseExtendedWaitUntil() throws {
        let yaml = """
        - extendedWaitUntil:
            text: "Loaded"
            timeout: 10000
        - takeScreenshot: "Ready"
        """

        let config = try MaestroFlowParser.parse(yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps[0].assertVisible, "Loaded")
        } else {
            XCTFail("Expected steps")
        }
    }

    func testParseStepsForRunFlow() throws {
        let yaml = """
        appId: com.example.app
        ---
        - tapOn: "Login"
        - inputText: "user@example.com"
        - tapOn: "Submit"
        """

        let steps = try MaestroFlowParser.parseSteps(yaml)
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps[0].tap, "Login")
        XCTAssertEqual(steps[1].type, "user@example.com")
        XCTAssertEqual(steps[2].tap, "Submit")
    }

    func testUnsupportedCommandsSkipped() throws {
        let yaml = """
        - launchApp
        - setPermissions:
            CAMERA: allow
        - pressKey: RETURN
        - evalScript: \u{0024}{output.x = 1}
        - tapOn: "Button"
        - takeScreenshot: "Result"
        """

        let config = try MaestroFlowParser.parse(yaml)
        // Only the tapOn should make it through as a step
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps.count, 1)
            XCTAssertEqual(steps[0].tap, "Button")
        } else {
            XCTFail("Expected steps")
        }
    }

    func testScreenshotAtStartCreatesLaunchScreen() throws {
        let yaml = """
        - launchApp
        - takeScreenshot: "Launch"
        - tapOn: "Next"
        - takeScreenshot: "Second"
        """

        let config = try MaestroFlowParser.parse(yaml)
        XCTAssertEqual(config.screens.count, 2)

        // First screenshot has no steps before it → launch
        if case .launch = config.screens[0].path {
            // correct
        } else {
            XCTFail("Expected launch path for first screen")
        }
        XCTAssertEqual(config.screens[0].name, "Launch")

        // Second has a tap step
        if case .steps(let steps) = config.screens[1].path {
            XCTAssertEqual(steps[0].tap, "Next")
        } else {
            XCTFail("Expected steps for second screen")
        }
    }

    func testAssertNotVisibleMapping() throws {
        let yaml = """
        - assertNotVisible: "Error Dialog"
        - assertNotVisible:
            text: "Loading Spinner"
        - takeScreenshot: "Clean"
        """

        let config = try MaestroFlowParser.parse(yaml)
        if case .steps(let steps) = config.screens[0].path {
            XCTAssertEqual(steps.count, 2)
            XCTAssertEqual(steps[0].assertNotVisible, "Error Dialog")
            XCTAssertEqual(steps[1].assertNotVisible, "Loading Spinner")
        } else {
            XCTFail("Expected steps")
        }
    }
}
