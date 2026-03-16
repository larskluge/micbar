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
            let results = [self.checkTranscription(), self.checkImproveWriting()]
            DispatchQueue.main.async {
                self.results = results
                self.isChecking = false
            }
        }
    }

    private func checkTranscription() -> DependencyStatus {
        return checkHTTP(name: "WhisperKit Server :50060", url: "http://localhost:50060/health")
    }

    private func checkImproveWriting() -> DependencyStatus {
        let proxy = checkHTTP(name: "LLM proxy :8317", url: "http://localhost:8317/v1/models")
        return proxy
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
