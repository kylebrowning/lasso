import Foundation

/// Streams `xcrun simctl spawn <udid> log stream` output into the current
/// process's stderr with a `[log]` prefix so simulator app logs interleave
/// naturally with grantiva and runner output.
///
/// Line-atomic: the underlying subprocess writes whole lines and we forward
/// them with a prefix, so you never see half a grantiva line mixed with half
/// a log line. Ordering across the two sources is best-effort — they're two
/// processes writing to two pipes, with no global clock — but within a given
/// stream, line order is preserved.
public final class LogStreamer: @unchecked Sendable {
    private var process: Process?
    private var stderrPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let lock = NSLock()
    private var stopped = false

    public init() {}

    /// Starts streaming simulator logs. Non-blocking. Call `stop()` to tear
    /// down. `predicate` is passed verbatim to `simctl log stream --predicate`;
    /// pass `nil` for no predicate (warning: very chatty).
    public func start(udid: String, predicate: String?, level: String?) throws {
        lock.lock()
        defer { lock.unlock() }

        guard process == nil else { return }

        var args = ["simctl", "spawn", udid, "log", "stream", "--style", "compact"]
        if let predicate, !predicate.isEmpty {
            args += ["--predicate", predicate]
        }
        if let level, !level.isEmpty {
            args += ["--level", level]
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        // Forward each readable chunk line-by-line with a [log] prefix.
        let forward: @Sendable (FileHandle) -> Void = { handle in
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                if data.isEmpty { return }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
                for (i, line) in lines.enumerated() {
                    // The final element of split(...) may be "" after a trailing
                    // newline — drop to avoid a bare "[log]" line.
                    if i == lines.count - 1 && line.isEmpty { continue }
                    let prefixed = "[log] \(line)\n"
                    FileHandle.standardError.write(Data(prefixed.utf8))
                }
            }
        }

        forward(outPipe.fileHandleForReading)
        forward(errPipe.fileHandleForReading)

        try p.run()

        process = p
        stdoutPipe = outPipe
        stderrPipe = errPipe
    }

    /// Stops the log stream subprocess. Safe to call multiple times.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard !stopped else { return }
        stopped = true

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
    }
}

/// Derives a sensible default `simctl log stream --predicate` value from a
/// bundle ID. Matches os_log subsystems that BEGIN with the bundle ID (the
/// convention), so apps using `Logger(subsystem: "com.example.app", …)` get
/// caught without extra config. Also matches the process image by bundle ID
/// as a fallback for apps that don't use unified logging subsystems.
public func defaultLogPredicate(forBundleID bundleID: String) -> String {
    "subsystem BEGINSWITH \"\(bundleID)\" OR processImagePath CONTAINS \"\(bundleID)\""
}
