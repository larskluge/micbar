import XCTest
import Foundation

/// Mirrors the `runImproveWriting` logic from ImproveWriting.swift so we can test
/// the subprocess handling: success, non-zero exit, empty output, command not found.
private func runImproveWriting(_ text: String, command: String) -> String? {
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

        if proc.terminationStatus != 0 {
            return nil
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let improved = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if improved.isEmpty {
            return nil
        }
        return improved
    } catch {
        return nil
    }
}

final class ImproveWritingTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeScript(contents: String) -> String {
        let path = tempDir.appendingPathComponent("test-script").path
        try! contents.write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o755)
        return path
    }

    // MARK: - Success cases

    func testSuccessReturnsImprovedText() {
        let script = makeScript(contents: "#!/bin/bash\nread input\necho \"improved: $input\"")
        let result = runImproveWriting("hello world", command: script)
        XCTAssertEqual(result, "improved: hello world")
    }

    func testStdinPassedToCommand() {
        let script = makeScript(contents: "#!/bin/bash\ncat")
        let result = runImproveWriting("the quick brown fox", command: script)
        XCTAssertEqual(result, "the quick brown fox")
    }

    func testOutputIsTrimmed() {
        let script = makeScript(contents: "#!/bin/bash\necho \"\"\necho \"  trimmed  \"\necho \"\"")
        let result = runImproveWriting("hello", command: script)
        XCTAssertEqual(result, "trimmed")
    }

    // MARK: - Failure cases: must return nil (not raw text)

    func testNonZeroExitReturnsNil() {
        let script = makeScript(contents: "#!/bin/bash\nexit 1")
        let result = runImproveWriting("hello", command: script)
        XCTAssertNil(result, "Non-zero exit must return nil, not fall back to raw text")
    }

    func testCommandNotFoundReturnsNil() {
        let result = runImproveWriting("hello", command: "nonexistent-command-\(UUID().uuidString)")
        XCTAssertNil(result, "Missing command must return nil, not fall back to raw text")
    }

    func testEmptyOutputReturnsNil() {
        let script = makeScript(contents: "#!/bin/bash\nexit 0")
        let result = runImproveWriting("hello", command: script)
        XCTAssertNil(result, "Empty output must return nil, not fall back to raw text")
    }

    func testWhitespaceOnlyOutputReturnsNil() {
        let script = makeScript(contents: "#!/bin/bash\necho \"   \"")
        let result = runImproveWriting("hello", command: script)
        XCTAssertNil(result, "Whitespace-only output must return nil, not fall back to raw text")
    }

    func testNonZeroExitWithOutputReturnsNil() {
        let script = makeScript(contents: "#!/bin/bash\necho \"some output\"\nexit 2")
        let result = runImproveWriting("hello", command: script)
        XCTAssertNil(result, "Non-zero exit must return nil even if there is stdout output")
    }
}
