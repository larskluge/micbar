import Foundation

struct TranscriptionResult: Equatable {
    let text: String?
    let error: String?
}

struct TranscriptionConfig {
    var url: String = "http://localhost:50060/v1/audio/transcriptions"
    var timeoutSeconds: TimeInterval = 60
}

// MARK: - Request building

func buildTranscriptionRequest(wavData: Data, config: TranscriptionConfig) -> URLRequest? {
    guard let url = URL(string: config.url) else { return nil }

    let boundary = UUID().uuidString
    var body = Data()

    // model field: required by WhisperKit's OpenAPI transport layer but the value
    // is ignored — the server always uses whatever model was loaded at startup.
    // See OpenAIHandler.swift in argmaxinc/WhisperKit.
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
    body.append("default\r\n".data(using: .utf8)!)

    // file field
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
    body.append(wavData)
    body.append("\r\n".data(using: .utf8)!)

    // closing boundary
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    request.timeoutInterval = config.timeoutSeconds
    return request
}

// MARK: - Response parsing

func parseTranscriptionResponse(data: Data?, response: URLResponse?, error: Error?) -> TranscriptionResult {
    if let error = error {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCannotConnectToHost || nsError.code == -1004 {
            return TranscriptionResult(text: nil, error: "WhisperKit server not running at localhost:50060")
        }
        return TranscriptionResult(text: nil, error: error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
        return TranscriptionResult(text: nil, error: "No response from WhisperKit server")
    }

    guard let data = data else {
        return TranscriptionResult(text: nil, error: "Empty response from WhisperKit server")
    }

    guard (200...299).contains(http.statusCode) else {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMsg = json["error"] as? String {
            return TranscriptionResult(text: nil, error: errorMsg)
        }
        return TranscriptionResult(text: nil, error: "WhisperKit server returned HTTP \(http.statusCode)")
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let text = json["text"] as? String else {
        return TranscriptionResult(text: nil, error: "Failed to parse transcription response")
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return TranscriptionResult(text: nil, error: "Transcription returned empty text")
    }
    return TranscriptionResult(text: trimmed, error: nil)
}

// MARK: - Public API

func runTranscription(
    wavData: Data,
    config: TranscriptionConfig = TranscriptionConfig(),
    client: HTTPClient = URLSessionHTTPClient(),
    log: Logger = .shared
) -> TranscriptionResult {
    log.info("transcription: sending \(wavData.count) bytes")
    let startTime = Date()

    guard let request = buildTranscriptionRequest(wavData: wavData, config: config) else {
        return TranscriptionResult(text: nil, error: "Failed to build transcription request")
    }

    var result = TranscriptionResult(text: nil, error: "Timeout")
    let semaphore = DispatchSemaphore(value: 0)

    client.sendRequest(request) { data, response, error in
        result = parseTranscriptionResponse(data: data, response: response, error: error)
        semaphore.signal()
    }

    _ = semaphore.wait(timeout: .now() + config.timeoutSeconds + 5)

    let elapsed = String(format: "%.1f", -startTime.timeIntervalSinceNow)

    if let text = result.text {
        log.info("transcription (\(text.count) chars) in \(elapsed)s: \(String(text.prefix(500)))")
    } else {
        log.warning("transcription failed in \(elapsed)s: \(result.error ?? "unknown")")
    }

    return result
}
