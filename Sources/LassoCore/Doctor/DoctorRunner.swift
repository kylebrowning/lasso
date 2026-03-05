import Foundation

public struct DoctorRunner: Sendable {
    public init() {}

    public func runAllChecks() async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        checks.append(await checkXcode())
        checks.append(await checkXcodeVersion())
        checks.append(await checkBootedSimulator())
        checks.append(await checkSimctlType())
        checks.append(checkAccessibilityPermission())
        checks.append(await checkAXe())
        checks.append(checkGitRepository())
        checks.append(checkLassoConfig())
        checks.append(checkLassoAuth())
        checks.append(checkGitHubToken())
        checks.append(await checkDriverCache())
        return checks
    }

    func checkXcode() async -> DoctorCheck {
        do {
            let path = try await shell("xcode-select -p")
            return DoctorCheck(name: "Xcode", status: .ok, message: path, fix: nil)
        } catch {
            return DoctorCheck(
                name: "Xcode", status: .error,
                message: "Xcode not found",
                fix: "Install Xcode from the App Store and run: xcode-select --install"
            )
        }
    }

    func checkXcodeVersion() async -> DoctorCheck {
        do {
            let version = try await shell("xcodebuild -version | head -1")
            return DoctorCheck(name: "Xcode Version", status: .ok, message: version, fix: nil)
        } catch {
            return DoctorCheck(
                name: "Xcode Version", status: .error,
                message: "Could not determine Xcode version",
                fix: "Ensure Xcode is properly installed"
            )
        }
    }

    func checkBootedSimulator() async -> DoctorCheck {
        do {
            let device = try await SimulatorManager.live.bootedDevice()
            return DoctorCheck(
                name: "Booted Simulator", status: .ok,
                message: "\(device.name) — \(device.runtime)", fix: nil
            )
        } catch {
            return DoctorCheck(
                name: "Booted Simulator", status: .warning,
                message: "No simulator booted",
                fix: "Run: lasso sim boot \"iPhone 16\""
            )
        }
    }

    func checkSimctlType() async -> DoctorCheck {
        do {
            let help = try await shell("xcrun simctl io --help 2>&1")
            if help.contains("type") {
                return DoctorCheck(
                    name: "Text Input", status: .ok,
                    message: "xcrun simctl io type available", fix: nil
                )
            }
            return DoctorCheck(
                name: "Text Input", status: .warning,
                message: "simctl type not available — requires Xcode 14.3+",
                fix: "Update Xcode"
            )
        } catch {
            return DoctorCheck(
                name: "Text Input", status: .warning,
                message: "Could not check simctl type support",
                fix: "Ensure Xcode command line tools are installed"
            )
        }
    }

    func checkAccessibilityPermission() -> DoctorCheck {
        DoctorCheck(
            name: "Accessibility Permission", status: .warning,
            message: "Run lasso doctor from a terminal with Accessibility permission",
            fix: "System Settings -> Privacy & Security -> Accessibility -> enable your terminal"
        )
    }

    func checkAXe() async -> DoctorCheck {
        guard let path = which("axe") else {
            return DoctorCheck(
                name: "AXe (optional)", status: .warning,
                message: "Not installed. CGEvent fallback active. Custom gesture recognizers may not respond.",
                fix: "brew install AXErunner/axe/axe"
            )
        }
        do {
            let version = try await shell("\(path) --version")
            return DoctorCheck(
                name: "AXe (optional)", status: .ok,
                message: "Found — \(version). Full gesture support enabled.", fix: nil
            )
        } catch {
            return DoctorCheck(
                name: "AXe (optional)", status: .ok,
                message: "Found at \(path)", fix: nil
            )
        }
    }

    func checkGitRepository() -> DoctorCheck {
        if FileManager.default.fileExists(atPath: ".git") {
            return DoctorCheck(name: "Git Repository", status: .ok, message: "Detected", fix: nil)
        }
        return DoctorCheck(
            name: "Git Repository", status: .warning,
            message: "Not a git repository",
            fix: "Run: git init"
        )
    }

    func checkLassoConfig() -> DoctorCheck {
        if FileManager.default.fileExists(atPath: "lasso.yml") {
            return DoctorCheck(name: "lasso.yml", status: .ok, message: "Found", fix: nil)
        }
        return DoctorCheck(
            name: "lasso.yml", status: .warning,
            message: "Not found",
            fix: "Run: lasso init"
        )
    }

    func checkLassoAuth() -> DoctorCheck {
        if ProcessInfo.processInfo.environment["LASSO_API_KEY"] != nil {
            return DoctorCheck(
                name: "Lasso Range Auth", status: .ok,
                message: "Authenticated via LASSO_API_KEY", fix: nil
            )
        }
        if let credentials = AuthStore.live.load() {
            let prefix = String(credentials.apiKey.prefix(8))
            return DoctorCheck(
                name: "Lasso Range Auth", status: .ok,
                message: "Authenticated via ~/.lasso/auth.json (\(prefix)...)", fix: nil
            )
        }
        return DoctorCheck(
            name: "Lasso Range Auth", status: .warning,
            message: "Not authenticated — remote baselines unavailable",
            fix: "Run: lasso auth login"
        )
    }

    func checkGitHubToken() -> DoctorCheck {
        if ProcessInfo.processInfo.environment["GITHUB_TOKEN"] != nil {
            return DoctorCheck(name: "GitHub Token", status: .ok, message: "GITHUB_TOKEN set", fix: nil)
        }
        return DoctorCheck(
            name: "GitHub Token", status: .warning,
            message: "GITHUB_TOKEN not set",
            fix: "Export GITHUB_TOKEN for PR comment posting"
        )
    }

    func checkDriverCache() async -> DoctorCheck {
        let cache = DriverCache.live
        if await cache.isValid() {
            if let info = DriverCache.loadInfo() {
                return DoctorCheck(
                    name: "Driver Cache", status: .ok,
                    message: "Cached for Xcode \(info.xcodeVersion) (\(info.xcodeBuildVersion))",
                    fix: nil
                )
            }
            return DoctorCheck(name: "Driver Cache", status: .ok, message: "Valid", fix: nil)
        }

        // Check if stale vs missing
        if DriverCache.loadInfo() != nil {
            return DoctorCheck(
                name: "Driver Cache", status: .warning,
                message: "Stale — Xcode version changed since last build",
                fix: "Run: lasso driver build"
            )
        }
        return DoctorCheck(
            name: "Driver Cache", status: .warning,
            message: "Not built — UI automation with navigation requires the driver",
            fix: "Run: lasso driver build"
        )
    }
}
