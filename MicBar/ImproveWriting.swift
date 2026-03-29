import Foundation

struct ImproveResult: Equatable {
    let text: String?
    let error: String?
}

/// Abstraction over HTTP so we can inject a mock in tests.
protocol HTTPClient {
    func sendRequest(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void)
}

/// Default implementation using URLSession.
struct URLSessionHTTPClient: HTTPClient {
    func sendRequest(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        URLSession.shared.dataTask(with: request, completionHandler: completion).resume()
    }
}

/// Configuration for the improve-writing LLM call.
struct ImproveWritingConfig {
    var url: String = "http://localhost:8317/v1/chat/completions"
    var model: String = "claude-sonnet-4-6"
    var systemPrompt: String = """
        You are a copy writer. Detect which language the user's input is in and always respond in the same language. \
        Return ONLY the improved text, nothing else — no XML tags, no explanations, no preamble.

        Write a slightly improved version of the user's input. Shorten sentences where it makes sense; \
        do not do this aggressively. Do not change meaning.
        """
    var timeoutSeconds: TimeInterval = 60
    var maxRetries: Int = 2
}

/// Configuration for the answer-question LLM call.
struct AnswerQuestionConfig {
    var url: String = "http://localhost:8317/v1/chat/completions"
    var model: String = "claude-sonnet-4-6"
    var systemPrompt: String = """
        You are a helpful assistant. Detect which language the user's input is in and always respond in the same language. \
        The user has spoken a question or request via voice transcription. Answer it concisely and directly.
        """
    var timeoutSeconds: TimeInterval = 60
    var maxRetries: Int = 2
}

// MARK: - Request building

func buildImproveRequest(text: String, config: ImproveWritingConfig) -> URLRequest? {
    guard let url = URL(string: config.url) else { return nil }

    let body: [String: Any] = [
        "model": config.model,
        "stream": false,
        "messages": [
            ["role": "system", "content": config.systemPrompt],
            ["role": "user", "content": text],
        ],
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    request.timeoutInterval = config.timeoutSeconds
    return request
}

// MARK: - Response parsing

func parseImproveResponse(data: Data?, response: URLResponse?, error: Error?) -> ImproveResult {
    if let error = error {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCannotConnectToHost || nsError.code == -1004 {
            return ImproveResult(text: nil, error: "LLM proxy not running at localhost:8317")
        }
        return ImproveResult(text: nil, error: error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
        return ImproveResult(text: nil, error: "No response from LLM proxy")
    }

    guard let data = data else {
        return ImproveResult(text: nil, error: "Empty response from LLM proxy")
    }

    guard (200...299).contains(http.statusCode) else {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorObj = json["error"] as? [String: Any],
           let errorMsg = errorObj["message"] as? String {
            return ImproveResult(text: nil, error: errorMsg)
        }
        return ImproveResult(text: nil, error: "LLM proxy returned HTTP \(http.statusCode)")
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let first = choices.first,
          let message = first["message"] as? [String: Any],
          let content = message["content"] as? String else {
        return ImproveResult(text: nil, error: "Failed to parse LLM response")
    }

    let improved = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if improved.isEmpty {
        return ImproveResult(text: nil, error: "LLM returned empty response")
    }
    return ImproveResult(text: improved, error: nil)
}

/// Whether a failed result is worth retrying (transient network/server errors).
func isRetryableError(_ result: ImproveResult) -> Bool {
    guard let error = result.error else { return false }
    let retryablePatterns = ["unexpected EOF", "connection reset", "timed out",
                             "HTTP 502", "HTTP 503", "HTTP 429"]
    return retryablePatterns.contains(where: { error.localizedCaseInsensitiveContains($0) })
}

// MARK: - Public API

/// Calls the LLM proxy to improve the given text. Blocks the calling thread.
func runImproveWriting(
    _ text: String,
    config: ImproveWritingConfig = ImproveWritingConfig(),
    client: HTTPClient = URLSessionHTTPClient(),
    log: Logger = .shared
) -> ImproveResult {
    let llmConfig = LLMCallConfig(
        url: config.url, model: config.model,
        systemPrompt: config.systemPrompt,
        timeoutSeconds: config.timeoutSeconds, maxRetries: config.maxRetries
    )
    return runLLMCall(text, label: "improve-writing", config: llmConfig, client: client, log: log)
}

/// Calls the LLM proxy to answer a question from the transcription. Blocks the calling thread.
func runAnswerQuestion(
    _ text: String,
    config: AnswerQuestionConfig = AnswerQuestionConfig(),
    client: HTTPClient = URLSessionHTTPClient(),
    log: Logger = .shared
) -> ImproveResult {
    let llmConfig = LLMCallConfig(
        url: config.url, model: config.model,
        systemPrompt: config.systemPrompt,
        timeoutSeconds: config.timeoutSeconds, maxRetries: config.maxRetries
    )
    return runLLMCall(text, label: "answer-question", config: llmConfig, client: client, log: log)
}

/// Configuration for the translate LLM call.
struct TranslateConfig {
    var url: String = "http://localhost:8317/v1/chat/completions"
    var model: String = "claude-sonnet-4-6"
    var timeoutSeconds: TimeInterval = 60
    var maxRetries: Int = 2

    static func systemPrompt(targetLanguage: String) -> String {
        """
        You are a translator. Detect the language of the user's input. \
        If the input is in \(targetLanguage), translate it back to the original language it was likely translated from. \
        If you cannot determine the original language, translate it to English. \
        If the input is NOT in \(targetLanguage), translate it into \(targetLanguage). \
        Return ONLY the translated text, nothing else — no XML tags, no explanations, no preamble.
        """
    }
}

/// Calls the LLM proxy to translate text to/from a target language. Blocks the calling thread.
func runTranslate(
    _ text: String,
    targetLanguage: String,
    config: TranslateConfig = TranslateConfig(),
    client: HTTPClient = URLSessionHTTPClient(),
    log: Logger = .shared
) -> ImproveResult {
    let llmConfig = LLMCallConfig(
        url: config.url, model: config.model,
        systemPrompt: TranslateConfig.systemPrompt(targetLanguage: targetLanguage),
        timeoutSeconds: config.timeoutSeconds, maxRetries: config.maxRetries
    )
    return runLLMCall(text, label: "translate-\(targetLanguage.lowercased())", config: llmConfig, client: client, log: log)
}

/// Internal shared config for LLM calls.
private struct LLMCallConfig {
    var url: String
    var model: String
    var systemPrompt: String
    var timeoutSeconds: TimeInterval
    var maxRetries: Int
}

/// Shared implementation for LLM calls. Blocks the calling thread.
private func runLLMCall(
    _ text: String,
    label: String,
    config: LLMCallConfig,
    client: HTTPClient,
    log: Logger
) -> ImproveResult {
    log.info("\(label) input (\(text.count) chars): \(String(text.prefix(500)))")
    let startTime = Date()

    let improveConfig = ImproveWritingConfig(
        url: config.url, model: config.model,
        systemPrompt: config.systemPrompt,
        timeoutSeconds: config.timeoutSeconds, maxRetries: config.maxRetries
    )
    guard let request = buildImproveRequest(text: text, config: improveConfig) else {
        return ImproveResult(text: nil, error: "Failed to build request")
    }

    var lastResult = ImproveResult(text: nil, error: "Timeout")

    for attempt in 1...(1 + config.maxRetries) {
        let semaphore = DispatchSemaphore(value: 0)

        client.sendRequest(request) { data, response, error in
            lastResult = parseImproveResponse(data: data, response: response, error: error)
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + config.timeoutSeconds + 5)

        let elapsed = String(format: "%.1f", -startTime.timeIntervalSinceNow)

        if lastResult.text != nil {
            log.info("\(label) output (\(lastResult.text!.count) chars) in \(elapsed)s: \(String(lastResult.text!.prefix(500)))")
            return lastResult
        }

        if isRetryableError(lastResult) && attempt <= config.maxRetries {
            log.info("\(label) attempt \(attempt) failed (\(lastResult.error ?? "unknown")), retrying...")
            continue
        }

        log.warning("\(label) failed in \(elapsed)s: \(lastResult.error ?? "unknown")")
        return lastResult
    }

    return lastResult
}
