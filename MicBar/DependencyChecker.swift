import Foundation
import SwiftUI

struct DependencyStatus: Identifiable {
    let id = UUID()
    let name: String
    var found: Bool
    var path: String?
    var error: String?
    var children: [DependencyStatus]

    init(name: String, found: Bool, path: String? = nil, error: String? = nil, children: [DependencyStatus] = []) {
        self.name = name
        self.found = found
        self.path = path
        self.error = error
        self.children = children
    }
}

final class DependencyChecker: ObservableObject {
    @Published var results: [DependencyStatus] = []
    @Published var isChecking = false

    func checkAll() {
        isChecking = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let results = [self.checkMictotext(), self.checkImproveWriting()]
            DispatchQueue.main.async {
                self.results = results
                self.isChecking = false
            }
        }
    }

    private func checkMictotext() -> DependencyStatus {
        let resolved = MicToTextProcess.resolveExecutable("mictotext")
        let ffmpeg = checkExecutable("ffmpeg")
        let whisperkit = checkExecutable("whisperkit-cli")
        let server = checkHTTP(name: "WhisperKit Server :50060", url: "http://localhost:50060/health")

        return DependencyStatus(
            name: "mictotext",
            found: resolved != nil,
            path: resolved,
            error: resolved == nil ? "Not found on PATH" : nil,
            children: [ffmpeg, whisperkit, server]
        )
    }

    private func checkImproveWriting() -> DependencyStatus {
        let resolved = resolveWithHomeBin("improve-writing")
        let proxy = checkHTTP(name: "LLM proxy :8317", url: "http://localhost:8317/v1/models")

        return DependencyStatus(
            name: "improve-writing",
            found: resolved != nil,
            path: resolved,
            error: resolved == nil ? "Not found on PATH" : nil,
            children: [proxy]
        )
    }

    private func checkExecutable(_ name: String) -> DependencyStatus {
        let resolved = MicToTextProcess.resolveExecutable(name)
        return DependencyStatus(
            name: name,
            found: resolved != nil,
            path: resolved,
            error: resolved == nil ? "Not found on PATH" : nil
        )
    }

    private func resolveWithHomeBin(_ name: String) -> String? {
        let homeBin = FileManager.default.homeDirectoryForCurrentUser.path + "/bin"
        let full = "\(homeBin)/\(name)"
        if FileManager.default.isExecutableFile(atPath: full) {
            return full
        }
        return MicToTextProcess.resolveExecutable(name)
    }

    private func checkHTTP(name: String, url urlString: String) -> DependencyStatus {
        guard let url = URL(string: urlString) else {
            return DependencyStatus(name: name, found: false, error: "Invalid URL")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var status = DependencyStatus(name: name, found: false, error: "Timeout")

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                status = DependencyStatus(name: name, found: false, error: error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                status = DependencyStatus(name: name, found: true)
            } else if let http = response as? HTTPURLResponse {
                status = DependencyStatus(name: name, found: false, error: "HTTP \(http.statusCode)")
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 4)

        return status
    }
}
