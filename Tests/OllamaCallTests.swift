import XCTest
import Foundation

// MARK: - Duplicated types from ImproveWriting.swift (can't import executable target)

private struct ImproveResult: Equatable {
    let text: String?
    let error: String?
}

/// Mirrors `parseOllamaResponse` in ImproveWriting.swift.
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

private func isRetryableError(_ result: ImproveResult) -> Bool {
    guard let error = result.error else { return false }
    let retryablePatterns = ["unexpected EOF", "connection reset", "timed out",
                             "HTTP 502", "HTTP 503", "HTTP 429"]
    return retryablePatterns.contains(where: { error.localizedCaseInsensitiveContains($0) })
}

private func http(_ code: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "http://test")!, statusCode: code, httpVersion: nil, headerFields: nil)!
}

private func jsonData(_ str: String) -> Data {
    str.data(using: .utf8)!
}

private func successJSON(content: String) -> Data {
    jsonData("""
    {"message":{"content":"\(content)"}}
    """)
}

// MARK: - Response Parsing: Success

final class ParseSuccessTests: XCTestCase {

    func testParsesContent() {
        let result = parseOllamaResponse(data: successJSON(content: "Better."), response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: "Better.", error: nil))
    }

    func testTrimsWhitespace() {
        let data = jsonData("""
        {"message":{"content":"  trimmed  \\n"}}
        """)
        let result = parseOllamaResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result.text, "trimmed")
    }

    func testMultilineContent() {
        let data = jsonData("""
        {"message":{"content":"Line 1.\\nLine 2."}}
        """)
        let result = parseOllamaResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result.text, "Line 1.\nLine 2.")
    }
}

// MARK: - Response Parsing: Empty / Malformed

final class ParseErrorTests: XCTestCase {

    func testEmptyContentReturnsError() {
        let data = jsonData("""
        {"message":{"content":"   "}}
        """)
        let result = parseOllamaResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Ollama returned empty response"))
    }

    func testMalformedJson() {
        let result = parseOllamaResponse(data: jsonData("not json"), response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Failed to parse Ollama response"))
    }

    func testMissingMessage() {
        let result = parseOllamaResponse(data: jsonData("{\"model\":\"x\"}"), response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Failed to parse Ollama response"))
    }

    func testMissingContentKey() {
        let data = jsonData("{\"message\":{\"role\":\"assistant\"}}")
        let result = parseOllamaResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Failed to parse Ollama response"))
    }
}

// MARK: - Response Parsing: Network Errors

final class ParseNetworkErrorTests: XCTestCase {

    func testConnectionRefused() {
        let err = NSError(domain: NSURLErrorDomain, code: -1004, userInfo: nil)
        let result = parseOllamaResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Ollama not running at localhost:11434"))
    }

    func testCannotConnectToHost() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let result = parseOllamaResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Ollama not running at localhost:11434"))
    }

    func testTimeoutError() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                          userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let result = parseOllamaResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "The request timed out."))
    }

    func testNoResponse() {
        let result = parseOllamaResponse(data: nil, response: nil, error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "No response from Ollama"))
    }

    func testNilData() {
        let result = parseOllamaResponse(data: nil, response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Empty response from Ollama"))
    }
}

// MARK: - Response Parsing: HTTP Errors

final class ParseHTTPErrorTests: XCTestCase {

    func testHTTP500IncludesBody() {
        let result = parseOllamaResponse(data: jsonData("boom"), response: http(500), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Ollama HTTP 500: boom"))
    }

    func testHTTP404IncludesBody() {
        let result = parseOllamaResponse(data: jsonData("model not found"), response: http(404), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Ollama HTTP 404: model not found"))
    }
}

// MARK: - Retry Logic

final class RetryLogicTests: XCTestCase {

    func testRetryableUnexpectedEOF() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil,
            error: "Post \"https://api.example.com/v1/chat\": unexpected EOF")))
    }

    func testRetryableConnectionReset() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "connection reset by peer")))
    }

    func testRetryableTimeout() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "The request timed out.")))
    }

    func testRetryableHTTP502() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "Ollama HTTP 502: bad gateway")))
    }

    func testRetryableHTTP503() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "Ollama HTTP 503: unavailable")))
    }

    func testRetryableHTTP429() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "Ollama HTTP 429: too many requests")))
    }

    func testNotRetryableParseError() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: nil, error: "Failed to parse Ollama response")))
    }

    func testNotRetryableConnectionRefused() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: nil, error: "Ollama not running at localhost:11434")))
    }

    func testNotRetryableSuccess() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: "improved", error: nil)))
    }

    func testNotRetryableHTTP400() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: nil, error: "Ollama HTTP 400: bad request")))
    }

    func testNotRetryableEmptyResponse() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: nil, error: "Ollama returned empty response")))
    }
}
