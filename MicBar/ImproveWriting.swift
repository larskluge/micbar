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

// MARK: - System prompts

/// System prompt for the improve-writing LLM call.
struct ImproveWritingConfig {
    var systemPrompt: String = """
        You are a copy writer. Detect which language the user's input is in and always respond in the same language. \
        Return ONLY the improved text, nothing else — no XML tags, no explanations, no preamble.

        Write a slightly improved version of the user's input. Shorten sentences where it makes sense; \
        do not do this aggressively. Do not change meaning.
        """
}

/// System prompt for the answer-question LLM call.
struct AnswerQuestionConfig {
    var systemPrompt: String = """
        You are a helpful assistant. Detect which language the user's input is in and always respond in the same language. \
        The user has spoken a question or request via voice transcription. Answer it concisely and directly.
        """
}

/// System prompt for the rewrite LLM call.
struct RewriteConfig {
    var systemPrompt: String = """
        You are an expert editor. Detect which language the user's input is in and always respond in the same language. \
        Return ONLY the rewritten text, nothing else — no XML tags, no explanations, no preamble.

        The user has dictated raw, unstructured thoughts via voice — a brainstorm full of half-finished sentences, \
        tangents, and repetition. Rewrite it into a single comprehensive, well-structured message in clear language. \
        Bring together all the points raised; reorganize and merge them so the result flows well; remove filler and \
        false starts. Preserve every distinct idea and the user's intent and tone. Do not add new ideas or information. \
        The result should read like a thoughtful message written for another person.
        """
}

/// System prompt for the summarize LLM call.
struct SummarizeConfig {
    var systemPrompt: String = """
        You are a concise summarizer. Detect which language the user's input is in and always respond in the same language. \
        Return ONLY a short summary of the text that feels appropriate for its length and content — no XML tags, no explanations, no preamble.
        """
}

/// System prompt for the key-points LLM call.
struct KeyPointsConfig {
    var systemPrompt: String = """
        You are an analyst who extracts key points. Detect which language the user's input is in and always respond in the same language. \
        Return ONLY a bullet-point list (using "•") of the essential points from the text. \
        Keep each point short and crisp — no fluff, no intro, no outro. Cover all key points without being overly verbose.
        """
}

/// System prompt for the translate LLM call.
struct TranslateConfig {
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

// MARK: - Retry

/// Whether a failed result is worth retrying (transient network/server errors).
func isRetryableError(_ result: ImproveResult) -> Bool {
    guard let error = result.error else { return false }
    let retryablePatterns = ["unexpected EOF", "connection reset", "timed out",
                             "HTTP 502", "HTTP 503", "HTTP 429"]
    return retryablePatterns.contains(where: { error.localizedCaseInsensitiveContains($0) })
}

// MARK: - Ollama

/// Configuration for a local Ollama LLM call.
struct OllamaConfig {
    var url: String = "http://localhost:11434/api/chat"
    var model: String = "gemma4:26b"
    var systemPrompt: String
    var timeoutSeconds: TimeInterval = 120
    var maxRetries: Int = 1
}

/// Calls the local Ollama server with a given prompt. Blocks the calling thread.
func runOllamaCall(
    _ text: String,
    label: String,
    config: OllamaConfig,
    client: HTTPClient = URLSessionHTTPClient(),
    log: Logger = .shared
) -> ImproveResult {
    log.info("\(label) input (\(text.count) chars): \(String(text.prefix(500)))")
    let startTime = Date()

    guard let url = URL(string: config.url) else {
        return ImproveResult(text: nil, error: "Invalid Ollama URL")
    }

    let body: [String: Any] = [
        "model": config.model,
        "stream": false,
        "think": false,
        "messages": [
            ["role": "system", "content": config.systemPrompt],
            ["role": "user", "content": text],
        ],
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
        return ImproveResult(text: nil, error: "Failed to build Ollama request")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    request.timeoutInterval = config.timeoutSeconds

    var lastResult = ImproveResult(text: nil, error: "Timeout")

    for attempt in 1...(1 + config.maxRetries) {
        let semaphore = DispatchSemaphore(value: 0)

        client.sendRequest(request) { data, response, error in
            lastResult = parseOllamaResponse(data: data, response: response, error: error)
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

/// Parses Ollama's response format (message.content instead of choices[0].message.content).
private func parseOllamaResponse(data: Data?, response: URLResponse?, error: Error?) -> ImproveResult {
    if let error = error {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCannotConnectToHost || nsError.code == -1004 {
            return ImproveResult(text: nil, error: "Ollama not running at localhost:11434")
        }
        return ImproveResult(text: nil, error: error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
        return ImproveResult(text: nil, error: "No response from Ollama")
    }

    guard let data = data else {
        return ImproveResult(text: nil, error: "Empty response from Ollama")
    }

    guard (200...299).contains(http.statusCode) else {
        if let body = String(data: data, encoding: .utf8) {
            return ImproveResult(text: nil, error: "Ollama HTTP \(http.statusCode): \(body.prefix(200))")
        }
        return ImproveResult(text: nil, error: "Ollama returned HTTP \(http.statusCode)")
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = json["message"] as? [String: Any],
          let content = message["content"] as? String else {
        return ImproveResult(text: nil, error: "Failed to parse Ollama response")
    }

    let improved = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if improved.isEmpty {
        return ImproveResult(text: nil, error: "Ollama returned empty response")
    }
    return ImproveResult(text: improved, error: nil)
}
