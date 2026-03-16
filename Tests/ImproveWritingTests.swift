import XCTest
import Foundation

// MARK: - Duplicated types from ImproveWriting.swift (can't import executable target)

private struct ImproveResult: Equatable {
    let text: String?
    let error: String?
}

private func parseImproveResponse(data: Data?, response: URLResponse?, error: Error?) -> ImproveResult {
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
    {"choices":[{"message":{"content":"\(content)"}}]}
    """)
}

// MARK: - Response Parsing: Success

final class ParseSuccessTests: XCTestCase {

    func testParsesContent() {
        let result = parseImproveResponse(data: successJSON(content: "Better."), response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: "Better.", error: nil))
    }

    func testTrimsWhitespace() {
        let data = jsonData("""
        {"choices":[{"message":{"content":"  trimmed  \\n"}}]}
        """)
        let result = parseImproveResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result.text, "trimmed")
    }

    func testMultilineContent() {
        let data = jsonData("""
        {"choices":[{"message":{"content":"Line 1.\\nLine 2."}}]}
        """)
        let result = parseImproveResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result.text, "Line 1.\nLine 2.")
    }
}

// MARK: - Response Parsing: Empty / Malformed

final class ParseErrorTests: XCTestCase {

    func testEmptyContentReturnsError() {
        let data = jsonData("""
        {"choices":[{"message":{"content":"   "}}]}
        """)
        let result = parseImproveResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "LLM returned empty response"))
    }

    func testMalformedJson() {
        let result = parseImproveResponse(data: jsonData("not json"), response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Failed to parse LLM response"))
    }

    func testMissingChoices() {
        let result = parseImproveResponse(data: jsonData("{\"model\":\"x\"}"), response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Failed to parse LLM response"))
    }

    func testEmptyChoicesArray() {
        let result = parseImproveResponse(data: jsonData("{\"choices\":[]}"), response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Failed to parse LLM response"))
    }

    func testMissingMessageKey() {
        let data = jsonData("{\"choices\":[{\"index\":0}]}")
        let result = parseImproveResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Failed to parse LLM response"))
    }

    func testMissingContentKey() {
        let data = jsonData("{\"choices\":[{\"message\":{\"role\":\"assistant\"}}]}")
        let result = parseImproveResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Failed to parse LLM response"))
    }
}

// MARK: - Response Parsing: Network Errors

final class ParseNetworkErrorTests: XCTestCase {

    func testConnectionRefused() {
        let err = NSError(domain: NSURLErrorDomain, code: -1004, userInfo: nil)
        let result = parseImproveResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "LLM proxy not running at localhost:8317"))
    }

    func testCannotConnectToHost() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let result = parseImproveResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "LLM proxy not running at localhost:8317"))
    }

    func testTimeoutError() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                          userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let result = parseImproveResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "The request timed out."))
    }

    func testNoResponse() {
        let result = parseImproveResponse(data: nil, response: nil, error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "No response from LLM proxy"))
    }

    func testNilData() {
        let result = parseImproveResponse(data: nil, response: http(200), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Empty response from LLM proxy"))
    }
}

// MARK: - Response Parsing: HTTP Errors

final class ParseHTTPErrorTests: XCTestCase {

    func testHTTP500() {
        let result = parseImproveResponse(data: jsonData("err"), response: http(500), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "LLM proxy returned HTTP 500"))
    }

    func testHTTP429WithJsonError() {
        let data = jsonData("{\"error\":{\"message\":\"Rate limit exceeded\"}}")
        let result = parseImproveResponse(data: data, response: http(429), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "Rate limit exceeded"))
    }

    func testHTTP502WithProxyError() {
        let data = jsonData("{\"error\":{\"message\":\"Post \\\"https://api.anthropic.com/v1/messages?beta=true\\\": unexpected EOF\"}}")
        let result = parseImproveResponse(data: data, response: http(502), error: nil)
        XCTAssertTrue(result.error!.contains("unexpected EOF"))
    }

    func testHTTP400WithPlainText() {
        let result = parseImproveResponse(data: jsonData("Bad Request"), response: http(400), error: nil)
        XCTAssertEqual(result, ImproveResult(text: nil, error: "LLM proxy returned HTTP 400"))
    }
}

// MARK: - Retry Logic

final class RetryLogicTests: XCTestCase {

    func testRetryableUnexpectedEOF() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil,
            error: "Post \"https://api.anthropic.com/v1/messages?beta=true\": unexpected EOF")))
    }

    func testRetryableConnectionReset() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "connection reset by peer")))
    }

    func testRetryableTimeout() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "The request timed out.")))
    }

    func testRetryableHTTP502() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "LLM proxy returned HTTP 502")))
    }

    func testRetryableHTTP503() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "LLM proxy returned HTTP 503")))
    }

    func testRetryableHTTP429() {
        XCTAssertTrue(isRetryableError(ImproveResult(text: nil, error: "LLM proxy returned HTTP 429")))
    }

    func testNotRetryableParseError() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: nil, error: "Failed to parse LLM response")))
    }

    func testNotRetryableConnectionRefused() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: nil, error: "LLM proxy not running at localhost:8317")))
    }

    func testNotRetryableSuccess() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: "improved", error: nil)))
    }

    func testNotRetryableHTTP400() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: nil, error: "LLM proxy returned HTTP 400")))
    }

    func testNotRetryableEmptyResponse() {
        XCTAssertFalse(isRetryableError(ImproveResult(text: nil, error: "LLM returned empty response")))
    }
}
