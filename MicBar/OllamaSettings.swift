import Foundation
import Combine

class OllamaSettings: ObservableObject {
    static let shared = OllamaSettings()

    private let modelKey = "ollamaSelectedModel"
    private let modeKey = "useLocalLLM"
    private let defaultModel = "gemma4:26b"

    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: modelKey)
        }
    }

    /// User's preferred mode. The actual mode used is determined by `effectiveUseLocal`.
    @Published var useLocal: Bool {
        didSet {
            UserDefaults.standard.set(useLocal, forKey: modeKey)
        }
    }

    @Published var availableModels: [String] = []
    @Published var isFetching = false
    @Published var ollamaReachable = false
    @Published var remoteReachable = false

    /// Resolves the actual mode: if only one backend is available, use that one.
    /// If both or neither are available, respect the user's preference.
    var effectiveUseLocal: Bool {
        if ollamaReachable && !remoteReachable { return true }
        if remoteReachable && !ollamaReachable { return false }
        return useLocal
    }

    init() {
        self.selectedModel = UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
        self.useLocal = UserDefaults.standard.bool(forKey: modeKey)
    }

    func probeAvailability() {
        probeHTTP("http://localhost:11434/api/tags") { [weak self] ok in
            DispatchQueue.main.async { self?.ollamaReachable = ok }
        }
        probeHTTP("http://localhost:8317/v1/models") { [weak self] ok in
            DispatchQueue.main.async { self?.remoteReachable = ok }
        }
    }

    private func probeHTTP(_ urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else { completion(false); return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            completion(ok)
        }.resume()
    }

    func fetchModels() {
        isFetching = true
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            isFetching = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { DispatchQueue.main.async { self?.isFetching = false } }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }

            let names = models.compactMap { $0["name"] as? String }.sorted()

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.availableModels = names
                // If selected model not in list, keep it anyway (it may not be pulled yet)
            }
        }.resume()
    }
}
