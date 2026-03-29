import Foundation
import SwiftUI

struct DependencyStatus: Identifiable {
    let id = UUID()
    let name: String
    let description: String?
    var found: Bool
    var path: String?
    var error: String?
    var installCommand: String?
    var children: [DependencyStatus]

    init(name: String, description: String? = nil, found: Bool, path: String? = nil, installCommand: String? = nil, error: String? = nil, children: [DependencyStatus] = []) {
        self.name = name
        self.description = description
        self.found = found
        self.path = path
        self.installCommand = installCommand
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
            let results = [self.checkTranscription(), self.checkImproveWriting()]
            DispatchQueue.main.async {
                self.results = results
                self.isChecking = false
            }
        }
    }

    private func checkTranscription() -> DependencyStatus {
        return checkHTTP(
            name: "WhisperKit Server :50060",
            description: "Converts recorded audio to text using on-device speech recognition.",
            url: "http://localhost:50060/health",
            installCommand: "brew install whisperkit-cli"
        )
    }

    private func checkImproveWriting() -> DependencyStatus {
        return checkHTTP(
            name: "LLM proxy :8317",
            description: "Rewrites raw transcripts for grammar and clarity. Optional.",
            url: "http://localhost:8317/v1/models",
            installCommand: "brew install cliproxyapi"
        )
    }

    private func checkHTTP(name: String, description: String? = nil, url urlString: String, installCommand: String? = nil) -> DependencyStatus {
        guard let url = URL(string: urlString) else {
            return DependencyStatus(name: name, description: description, found: false, installCommand: installCommand, error: "Invalid URL")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var status = DependencyStatus(name: name, description: description, found: false, installCommand: installCommand, error: "Timeout")

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                status = DependencyStatus(name: name, description: description, found: false, installCommand: installCommand, error: error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                status = DependencyStatus(name: name, description: description, found: true, installCommand: installCommand)
            } else if let http = response as? HTTPURLResponse {
                status = DependencyStatus(name: name, description: description, found: false, installCommand: installCommand, error: "HTTP \(http.statusCode)")
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 4)

        return status
    }
}
