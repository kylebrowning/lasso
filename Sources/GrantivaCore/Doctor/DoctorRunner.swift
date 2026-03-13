import Foundation

public struct DoctorRunner: Sendable {
    public init() {}

    public func runAllChecks() async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []

        // Required
        checks.append(await checkXcode())
        checks.append(await checkXcodeVersion())
        checks.append(await checkBootedSimulator())
        checks.append(await checkRunner())

        // Project
        checks.append(checkGrantivaConfig())
        checks.append(checkGitRepository())

        // CI / Cloud
        checks.append(checkGrantivaAuth())
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

    func checkRunner() async -> DoctorCheck {
        let fm = FileManager.default
        let runnerPath = RunnerManager.binaryPath
        if fm.fileExists(atPath: runnerPath) {
            return DoctorCheck(
                name: "Runner", status: .ok,
                message: "grantiva-runner \(RunnerManager.runnerVersion)",
                fix: nil
            )
        }
        return DoctorCheck(
            name: "Runner", status: .warning,
            message: "Not extracted — will be extracted on first use",
            fix: "Run: grantiva runner install"
        )
    }

    func checkGrantivaConfig() -> DoctorCheck {
        if FileManager.default.fileExists(atPath: "grantiva.yml") {
            return DoctorCheck(name: "grantiva.yml", status: .ok, message: "Found", fix: nil, section: .project)
        }
        return DoctorCheck(
            name: "grantiva.yml", status: .warning,
            message: "Not found",
            fix: "Run: grantiva init",
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

    func checkGrantivaAuth() -> DoctorCheck {
        if ProcessInfo.processInfo.environment["GRANTIVA_API_KEY"] != nil {
            return DoctorCheck(
                name: "Grantiva Auth", status: .ok,
                message: "Authenticated via GRANTIVA_API_KEY", fix: nil, section: .cloud
            )
        }
        if let credentials = AuthStore.live.load() {
            let prefix = String(credentials.apiKey.prefix(8))
            return DoctorCheck(
                name: "Grantiva Auth", status: .ok,
                message: "Authenticated via ~/.grantiva/auth.json (\(prefix)...)", fix: nil, section: .cloud
            )
        }
        return DoctorCheck(
            name: "Grantiva Auth", status: .warning,
            message: "Not authenticated — remote baselines unavailable",
            fix: "Run: grantiva auth login",
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
            fix: "Install the GitHub App from your Grantiva dashboard settings",
            section: .cloud
        )
    }
}
