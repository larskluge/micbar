import Foundation

enum WhisperKitLaunchAgent {
    static let label = "com.la0x.micbar.whisperkit-serve"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func install() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/opt/homebrew/bin/whisperkit-cli",
                "serve",
                "--host",
                "127.0.0.1",
                "--model-path",
                "\(home)/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930",
            ],
            "EnvironmentVariables": [
                "PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": "\(home)/Library/Logs/whisperkit-serve.log",
            "StandardErrorPath": "\(home)/Library/Logs/whisperkit-serve.log",
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        let result = Process.launchctl(["load", plistURL.path])
        if result != 0 {
            Logger.shared.warning("launchctl load exited with \(result)")
        }
    }

    static func uninstall() throws {
        if isInstalled {
            let result = Process.launchctl(["unload", plistURL.path])
            if result != 0 {
                Logger.shared.warning("launchctl unload exited with \(result)")
            }
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}

extension Process {
    @discardableResult
    static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
