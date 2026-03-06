import Foundation

public struct DoctorRunner: Sendable {
    public init() {}

    public func runAllChecks() async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []

        // Required
        checks.append(await checkXcode())
        checks.append(await checkXcodeVersion())
        checks.append(await checkBootedSimulator())
        checks.append(await checkSimctlType())
        checks.append(await checkDriverCache())

        // Project
        checks.append(checkLassoConfig())
        checks.append(checkGitRepository())

        // CI / Cloud
        checks.append(checkLassoAuth())
        checks.append(checkGitHubApp())

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
                fix: "Run: xcrun simctl boot \"iPhone 16\""
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

        if DriverCache.loadInfo() != nil {
            return DoctorCheck(
                name: "Driver Cache", status: .warning,
                message: "Stale — Xcode version changed since last build",
                fix: "Run: lasso driver build"
            )
        }
        return DoctorCheck(
            name: "Driver Cache", status: .warning,
            message: "Not built — UI automation requires the driver",
            fix: "Run: lasso driver build"
        )
    }

    func checkLassoConfig() -> DoctorCheck {
        if FileManager.default.fileExists(atPath: "lasso.yml") {
            return DoctorCheck(name: "lasso.yml", status: .ok, message: "Found", fix: nil, section: .project)
        }
        return DoctorCheck(
            name: "lasso.yml", status: .warning,
            message: "Not found",
            fix: "Run: lasso init",
            section: .project
        )
    }

    func checkGitRepository() -> DoctorCheck {
        if FileManager.default.fileExists(atPath: ".git") {
            return DoctorCheck(name: "Git Repository", status: .ok, message: "Detected", fix: nil, section: .project)
        }
        return DoctorCheck(
            name: "Git Repository", status: .warning,
            message: "Not a git repository",
            fix: "Run: git init",
            section: .project
        )
    }

    func checkLassoAuth() -> DoctorCheck {
        if ProcessInfo.processInfo.environment["LASSO_API_KEY"] != nil {
            return DoctorCheck(
                name: "Lasso Range Auth", status: .ok,
                message: "Authenticated via LASSO_API_KEY", fix: nil, section: .cloud
            )
        }
        if let credentials = AuthStore.live.load() {
            let prefix = String(credentials.apiKey.prefix(8))
            return DoctorCheck(
                name: "Lasso Range Auth", status: .ok,
                message: "Authenticated via ~/.lasso/auth.json (\(prefix)...)", fix: nil, section: .cloud
            )
        }
        return DoctorCheck(
            name: "Lasso Range Auth", status: .warning,
            message: "Not authenticated — remote baselines unavailable",
            fix: "Run: lasso auth login",
            section: .cloud
        )
    }

    func checkGitHubApp() -> DoctorCheck {
        if ProcessInfo.processInfo.environment["GITHUB_APP_ID"] != nil,
           ProcessInfo.processInfo.environment["GITHUB_APP_PRIVATE_KEY"] != nil {
            return DoctorCheck(name: "GitHub App", status: .ok, message: "GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY set", fix: nil, section: .cloud)
        }
        return DoctorCheck(
            name: "GitHub App", status: .warning,
            message: "GitHub App not configured — Check Runs won't be posted",
            fix: "Install the GitHub App from your Lasso Range dashboard settings",
            section: .cloud
        )
    }
}
