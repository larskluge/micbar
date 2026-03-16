import Foundation

struct ImproveResult {
    let text: String?
    let error: String?
}

private let llmProxyURL = "http://localhost:8317/v1/chat/completions"
private let llmModel = "claude-sonnet-4-6"
private let systemPrompt = """
    You are a copy writer. Detect which language the user's input is in and always respond in the same language. \
    Return ONLY the improved text, nothing else — no XML tags, no explanations, no preamble.

    Write a slightly improved version of the user's input. Shorten sentences where it makes sense; \
    do not do this aggressively. Do not change meaning.
    """

/// Calls the LLM proxy to improve the given text. Blocks the calling thread.
func runImproveWriting(_ text: String, log: Logger = .shared) -> ImproveResult {
    log.info("improve-writing input (\(text.count) chars): \(String(text.prefix(500)))")
    let startTime = Date()

    guard let url = URL(string: llmProxyURL) else {
        return ImproveResult(text: nil, error: "Invalid LLM proxy URL")
    }

    let body: [String: Any] = [
        "model": llmModel,
        "stream": false,
        "messages": [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text],
        ],
    ]

    guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
        return ImproveResult(text: nil, error: "Failed to encode request")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    request.timeoutInterval = 60

    let semaphore = DispatchSemaphore(value: 0)
    var result = ImproveResult(text: nil, error: "Timeout")

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        let elapsed = String(format: "%.1f", -startTime.timeIntervalSinceNow)

        if let error = error {
            let msg: String
            let nsError = error as NSError
            if nsError.code == NSURLErrorCannotConnectToHost ||
               nsError.code == -1004 /* connection refused */ {
                msg = "LLM proxy not running at localhost:8317"
            } else {
                msg = error.localizedDescription
            }
            log.warning("improve-writing failed in \(elapsed)s: \(msg)")
            result = ImproveResult(text: nil, error: msg)
            semaphore.signal()
            return
        }

        guard let http = response as? HTTPURLResponse else {
            log.warning("improve-writing: no HTTP response")
            result = ImproveResult(text: nil, error: "No response from LLM proxy")
            semaphore.signal()
            return
        }

        guard let data = data else {
            log.warning("improve-writing: no data in response")
            result = ImproveResult(text: nil, error: "Empty response from LLM proxy")
            semaphore.signal()
            return
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let msg = "LLM proxy returned HTTP \(http.statusCode)"
            log.warning("improve-writing failed in \(elapsed)s: \(msg) — \(String(body.prefix(300)))")
            // Try to extract error message from JSON response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let errorMsg = errorObj["message"] as? String {
                result = ImproveResult(text: nil, error: errorMsg)
            } else {
                result = ImproveResult(text: nil, error: msg)
            }
            semaphore.signal()
            return
        }

        // Parse the OpenAI-compatible response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            log.warning("improve-writing: failed to parse response")
            result = ImproveResult(text: nil, error: "Failed to parse LLM response")
            semaphore.signal()
            return
        }

        let improved = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if improved.isEmpty {
            log.warning("improve-writing: empty content in \(elapsed)s")
            result = ImproveResult(text: nil, error: "LLM returned empty response")
        } else {
            log.info("improve-writing output (\(improved.count) chars) in \(elapsed)s: \(String(improved.prefix(500)))")
            result = ImproveResult(text: improved, error: nil)
        }
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 65)

    return result
}
