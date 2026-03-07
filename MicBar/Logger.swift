import Foundation

final class Logger {
    static let shared = Logger()

    private let queue = DispatchQueue(label: "com.aekym.micbar.logger")
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        return f
    }()

    private init() {
        let logPath = NSHomeDirectory() + "/Library/Logs/micbar.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logPath)
        fileHandle?.seekToEndOfFile()
    }

    deinit {
        fileHandle?.closeFile()
    }

    private func log(_ level: String, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)\n"
        queue.async { [weak self] in
            if let data = line.data(using: .utf8) {
                self?.fileHandle?.write(data)
            }
        }
    }

    func info(_ message: String) { log("INFO", message) }
    func debug(_ message: String) { log("DEBUG", message) }
    func warning(_ message: String) { log("WARNING", message) }
}
