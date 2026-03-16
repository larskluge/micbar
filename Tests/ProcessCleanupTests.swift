import XCTest
import Foundation

/// Tests for process cleanup behavior matching MicToTextProcess patterns.
/// Verifies that child processes (like FFmpeg) don't survive when the
/// parent is stopped or the app terminates.
///
/// Can't import executable target, so we test the spawn/kill patterns directly.

final class ProcessCleanupTests: XCTestCase {

    // MARK: - Helpers

    /// Spawn a process in its own process group (mirrors MicToTextProcess).
    /// Redirects stdout/stderr to /dev/null so orphaned children don't hold
    /// the test runner's FDs open.
    private func spawnInOwnGroup(_ executable: String, args: [String] = []) -> pid_t {
        var pid: pid_t = 0

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        let devnull = open("/dev/null", O_WRONLY)
        posix_spawn_file_actions_adddup2(&fileActions, devnull, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, devnull, STDERR_FILENO)
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
            close(devnull)
        }

        var spawnAttrs: posix_spawnattr_t?
        posix_spawnattr_init(&spawnAttrs)
        posix_spawnattr_setflags(&spawnAttrs, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&spawnAttrs, 0)
        defer { posix_spawnattr_destroy(&spawnAttrs) }

        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(executable)] + args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        let result = posix_spawnp(&pid, executable, &fileActions, &spawnAttrs, argv, environ)
        XCTAssertEqual(result, 0, "Failed to spawn \(executable)")
        return pid
    }

    private func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    private func writeScript(_ content: String) throws -> String {
        let path = NSTemporaryDirectory() + "micbar_test_\(UUID().uuidString).sh"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o755)
        return path
    }

    /// Read child PIDs from a temp file (scripts write PIDs there).
    private func childPidsFromFile(_ path: String, timeout: UInt32 = 500_000) -> [pid_t] {
        var elapsed: UInt32 = 0
        let step: UInt32 = 50_000
        while elapsed < timeout {
            if let content = try? String(contentsOfFile: path, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\n")
                    .compactMap { pid_t($0) }
            }
            usleep(step)
            elapsed += step
        }
        return []
    }

    private func forceCleanup(_ pids: [pid_t]) {
        for p in pids where isProcessAlive(p) {
            kill(p, SIGKILL)
            usleep(50_000)
        }
    }

    // MARK: - Tests

    /// Baseline: SIGINT to process group kills a normal process.
    func testSIGINTKillsNormalProcess() {
        let pid = spawnInOwnGroup("/bin/sleep", args: ["999"])
        XCTAssertTrue(isProcessAlive(pid))

        kill(-pid, SIGINT)
        var status: Int32 = 0
        waitpid(pid, &status, 0)

        XCTAssertFalse(isProcessAlive(pid))
    }

    /// A SIGINT-resistant process survives SIGINT but dies to SIGKILL.
    /// This simulates FFmpeg sometimes not responding to SIGINT.
    func testSIGINTResistantProcessNeedsSIGKILL() throws {
        let script = try writeScript("#!/bin/bash\ntrap '' INT\nsleep 999")
        defer { unlink(script) }

        let pid = spawnInOwnGroup("/bin/bash", args: [script])
        usleep(150_000)
        XCTAssertTrue(isProcessAlive(pid))

        kill(-pid, SIGINT)
        usleep(300_000)
        XCTAssertTrue(isProcessAlive(pid), "SIGINT-resistant process should survive SIGINT")

        kill(-pid, SIGKILL)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        XCTAssertFalse(isProcessAlive(pid), "SIGKILL must always work")
    }

    /// Core bug: parent (mictotext) exits on SIGINT, but child (FFmpeg) ignores
    /// SIGINT and becomes an orphan. Current stop() only waitpid's on parent
    /// and then sets pid=0, losing the process group reference.
    func testOrphanedChildSurvivesSIGINT_CurrentBug() throws {
        let pidFile = NSTemporaryDirectory() + "micbar_test_pids_\(UUID().uuidString)"
        let script = try writeScript("""
        #!/bin/bash
        bash -c 'trap "" INT; sleep 999' &
        echo $! > \(pidFile)
        trap 'exit 0' INT
        sleep 999
        """)
        defer { unlink(script); unlink(pidFile) }

        let pid = spawnInOwnGroup("/bin/bash", args: [script])
        let childPids = childPidsFromFile(pidFile)
        XCTAssertEqual(childPids.count, 1, "Should have 1 child PID")
        let childPid = childPids[0]

        // Simulate current buggy stop(): SIGINT + waitpid on parent only
        kill(-pid, SIGINT)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        // Current code: pid = 0 (loses pgid reference)

        usleep(200_000)
        let orphanAlive = isProcessAlive(childPid)
        XCTAssertTrue(orphanAlive, "Bug: child survives because only parent was waited on")

        // Cleanup
        forceCleanup([childPid])
    }

    /// The fix: after waitpid on parent, send SIGKILL to the saved process group
    /// to clean up any surviving children.
    func testSIGKILLToGroupAfterWaitpidKillsOrphans() throws {
        let pidFile = NSTemporaryDirectory() + "micbar_test_pids_\(UUID().uuidString)"
        let script = try writeScript("""
        #!/bin/bash
        bash -c 'trap "" INT; sleep 999' &
        echo $! > \(pidFile)
        trap 'exit 0' INT
        sleep 999
        """)
        defer { unlink(script); unlink(pidFile) }

        let pid = spawnInOwnGroup("/bin/bash", args: [script])
        let childPids = childPidsFromFile(pidFile)
        XCTAssertEqual(childPids.count, 1)
        let childPid = childPids[0]

        // FIXED stop() behavior:
        let pgid = pid  // Save process group ID BEFORE clearing pid

        kill(-pgid, SIGINT)
        var status: Int32 = 0
        waitpid(pid, &status, 0)

        // FIX: SIGKILL the entire process group to clean up survivors
        kill(-pgid, SIGKILL)
        usleep(200_000)

        XCTAssertFalse(isProcessAlive(childPid), "SIGKILL to group should kill orphaned child")
    }

    /// waitpid with WNOHANG polling + SIGKILL escalation for processes that
    /// ignore SIGINT entirely (both parent and children stuck).
    func testWaitpidTimeoutWithSIGKILLEscalation() throws {
        let script = try writeScript("#!/bin/bash\ntrap '' INT\nsleep 999")
        defer { unlink(script) }

        let pid = spawnInOwnGroup("/bin/bash", args: [script])
        usleep(100_000)

        kill(-pid, SIGINT)

        // Poll with WNOHANG (max ~500ms)
        var status: Int32 = 0
        var reaped = false
        for _ in 0..<5 {
            if waitpid(pid, &status, WNOHANG) > 0 {
                reaped = true
                break
            }
            usleep(100_000)
        }

        XCTAssertFalse(reaped, "SIGINT-resistant process should not be reaped by polling")

        // Escalate to SIGKILL
        kill(-pid, SIGKILL)
        waitpid(pid, &status, 0)
        XCTAssertFalse(isProcessAlive(pid))
    }

    /// Multiple children in the same process group all get killed by group SIGKILL.
    func testMultipleChildrenInGroupAllKilled() throws {
        let pidFile = NSTemporaryDirectory() + "micbar_test_pids_\(UUID().uuidString)"
        let script = try writeScript("""
        #!/bin/bash
        sleep 999 &
        PID1=$!
        sleep 999 &
        PID2=$!
        echo "$PID1" > \(pidFile)
        echo "$PID2" >> \(pidFile)
        trap 'exit 0' INT
        wait
        """)
        defer { unlink(script); unlink(pidFile) }

        let pid = spawnInOwnGroup("/bin/bash", args: [script])
        let childPids = childPidsFromFile(pidFile)
        XCTAssertEqual(childPids.count, 2, "Should have 2 child PIDs")

        let pgid = pid
        kill(-pgid, SIGINT)
        var status: Int32 = 0
        waitpid(pid, &status, 0)

        // SIGKILL the group to clean up children
        kill(-pgid, SIGKILL)
        usleep(200_000)

        for childPid in childPids {
            XCTAssertFalse(isProcessAlive(childPid), "Child \(childPid) should be dead after group SIGKILL")
        }
    }
}
