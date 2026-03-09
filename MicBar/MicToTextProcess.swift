import Foundation

final class MicToTextProcess {
    private var pid: pid_t = 0
    private var stdoutReadFD: Int32 = -1
    private var stderrReadFD: Int32 = -1
    private let log = Logger.shared
    private var stderrMonitorQueue: DispatchQueue?

    var onReady: (() -> Void)?

    func start() -> Bool {
        var stdoutPipe: [Int32] = [0, 0]
        var stderrPipe: [Int32] = [0, 0]
        guard pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            log.warning("failed to create pipes")
            return false
        }

        stdoutReadFD = stdoutPipe[0]
        stderrReadFD = stderrPipe[0]

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[1])
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe[1])

        var spawnAttrs: posix_spawnattr_t?
        posix_spawnattr_init(&spawnAttrs)
        posix_spawnattr_setflags(&spawnAttrs, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&spawnAttrs, 0)

        guard let resolvedPath = MicToTextProcess.resolveExecutable("mictotext") else {
            log.warning("mictotext not found on PATH")
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&spawnAttrs)
            close(stdoutPipe[0]); close(stdoutPipe[1])
            close(stderrPipe[0]); close(stderrPipe[1])
            return false
        }
        log.info("resolved mictotext: \(resolvedPath)")

        let argv: [UnsafeMutablePointer<CChar>?] = [
            strdup("mictotext"),
            nil
        ]
        defer { argv.forEach { free($0) } }

        let env = buildEnvironment()
        defer { env.forEach { free($0) } }

        let result = posix_spawnp(&pid, resolvedPath, &fileActions, &spawnAttrs, argv, env)

        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&spawnAttrs)

        close(stdoutPipe[1])
        close(stderrPipe[1])

        if result != 0 {
            log.warning("posix_spawnp failed: \(result)")
            close(stdoutReadFD)
            close(stderrReadFD)
            stdoutReadFD = -1
            stderrReadFD = -1
            return false
        }

        log.info("mictotext started PID=\(pid)")
        startStderrMonitor()
        logProcessTree()
        return true
    }

    func stop() -> String? {
        guard pid > 0 else {
            log.warning("stop: no process")
            return nil
        }

        log.info("stopping mictotext PID=\(pid)")
        kill(-pid, SIGINT)
        log.debug("SIGINT sent, reading stdout...")

        let stdoutData = readAll(fd: stdoutReadFD)
        close(stdoutReadFD)
        stdoutReadFD = -1

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let exitCode = (status & 0x7f) == 0 ? Int32((status >> 8) & 0xff) : Int32(-1)
        log.info("mictotext exited rc=\(exitCode)")

        close(stderrReadFD)
        stderrReadFD = -1
        pid = 0

        let text = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        log.info("transcription (\(text.count) chars): \(String(text.prefix(500)))")
        return text
    }

    func forceKill() {
        guard pid > 0 else { return }
        log.info("killing mictotext PID=\(pid)")
        Darwin.kill(-pid, SIGKILL)
        close(stdoutReadFD)
        stdoutReadFD = -1
        close(stderrReadFD)
        stderrReadFD = -1
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        log.info("mictotext killed")
        pid = 0
    }

    var isRunning: Bool { pid > 0 }

    private func readAll(fd: Int32) -> Data {
        var data = Data()
        let bufSize = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while true {
            let n = read(fd, buf, bufSize)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }

    private func startStderrMonitor() {
        let fd = stderrReadFD
        let queue = DispatchQueue(label: "com.aekym.micbar.stderr")
        stderrMonitorQueue = queue
        queue.async { [weak self] in
            guard let self = self else { return }
            let bufSize = 1024
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate() }
            var lineBuffer = Data()
            var readyFired = false

            while true {
                let n = read(fd, buf, bufSize)
                if n <= 0 { break }
                lineBuffer.append(buf, count: n)

                while let newlineRange = lineBuffer.range(of: Data([0x0A])) {
                    let lineData = lineBuffer.subdata(in: 0..<newlineRange.lowerBound)
                    lineBuffer.removeSubrange(0..<newlineRange.upperBound)

                    if let line = String(data: lineData, encoding: .utf8) {
                        self.log.debug("stderr: \(line)")
                        if !readyFired && line.contains("Recording now") {
                            readyFired = true
                            self.log.info("mictotext ready, recording")
                            DispatchQueue.main.async { self.onReady?() }
                        }
                    }
                }
            }
        }
    }

    private func logProcessTree() {
        let spawnedPid = pid
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-o", "pid,ppid,pgid,nice,pri,command", "-g", "\(spawnedPid)"]
            let pipe = Pipe()
            ps.standardOutput = pipe
            ps.standardError = FileHandle.nullDevice
            do {
                try ps.run()
                ps.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    self.log.info("process tree:\n\(output)")
                }
            } catch {
                self.log.warning("logProcessTree error: \(error)")
            }
        }
    }

    static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static func resolveExecutable(_ name: String) -> String? {
        let fm = FileManager.default
        // Check current PATH first, then common locations
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        let allDirs = pathDirs + searchPaths.filter { !pathDirs.contains($0) }
        for dir in allDirs {
            let full = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: full) {
                return full
            }
        }
        return nil
    }

    private func buildEnvironment() -> [UnsafeMutablePointer<CChar>?] {
        var env: [UnsafeMutablePointer<CChar>?] = []
        let currentEnv = ProcessInfo.processInfo.environment
        for (key, value) in currentEnv {
            if key == "PATH" {
                let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
                let newPath = value.contains("/opt/homebrew/bin") ? value : "\(extraPaths):\(value)"
                env.append(strdup("PATH=\(newPath)"))
            } else {
                env.append(strdup("\(key)=\(value)"))
            }
        }
        env.append(nil)
        return env
    }
}
