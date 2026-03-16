import Foundation

struct ImproveResult {
    let text: String?
    let error: String?
}

/// Runs `improve-writing` CLI with the given text on stdin, returns improved text or error details.
func runImproveWriting(_ text: String, command: String = "improve-writing", log: Logger = .shared) -> ImproveResult {
    log.info("improve-writing input (\(text.count) chars): \(String(text.prefix(500)))")
    let startTime = Date()

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [command]

    var environment = ProcessInfo.processInfo.environment
    let homeBin = FileManager.default.homeDirectoryForCurrentUser.path + "/bin"
    let extraPaths = [homeBin, "/opt/homebrew/bin", "/usr/local/bin"]
    if let path = environment["PATH"] {
        let missing = extraPaths.filter { !path.contains($0) }
        if !missing.isEmpty {
            environment["PATH"] = missing.joined(separator: ":") + ":" + path
        }
    }
    proc.environment = environment

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    proc.standardInput = stdinPipe
    proc.standardOutput = stdoutPipe
    proc.standardError = stderrPipe

    do {
        try proc.run()
        stdinPipe.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
        stdinPipe.fileHandleForWriting.closeFile()

        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + 60)
        timer.setEventHandler { [weak proc] in proc?.terminate() }
        timer.resume()

        proc.waitUntilExit()
        timer.cancel()

        let elapsed = -startTime.timeIntervalSinceNow
        log.info("improve-writing rc=\(proc.terminationStatus), took \(String(format: "%.1f", elapsed))s")

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrStr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stderrStr.isEmpty {
            log.debug("improve-writing stderr: \(String(stderrStr.prefix(500)))")
        }

        if proc.terminationStatus != 0 {
            let msg = stderrStr.isEmpty ? "Exit code \(proc.terminationStatus)" : stderrStr
            log.warning("improve-writing failed with exit code \(proc.terminationStatus)")
            return ImproveResult(text: nil, error: msg)
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let improved = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if improved.isEmpty {
            log.warning("improve-writing returned empty output")
            return ImproveResult(text: nil, error: "Returned empty output")
        }
        log.info("improve-writing output (\(improved.count) chars): \(String(improved.prefix(500)))")
        return ImproveResult(text: improved, error: nil)
    } catch {
        log.warning("improve-writing error: \(error)")
        return ImproveResult(text: nil, error: error.localizedDescription)
    }
}
