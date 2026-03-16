import XCTest
import Foundation

/// Parses an OpenAI-compatible chat completions JSON response, extracting the content.
/// Mirrors the parsing logic in ImproveWriting.swift.
private func parseCompletionResponse(_ data: Data) -> (text: String?, error: String?) {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let first = choices.first,
          let message = first["message"] as? [String: Any],
          let content = message["content"] as? String else {
        return (nil, "Failed to parse LLM response")
    }
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return (nil, "LLM returned empty response")
    }
    return (trimmed, nil)
}

/// Parses an OpenAI-compatible error JSON response.
private func parseErrorResponse(_ data: Data) -> String? {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let errorObj = json["error"] as? [String: Any],
       let errorMsg = errorObj["message"] as? String {
        return errorMsg
    }
    return nil
}

final class ImproveWritingTests: XCTestCase {

    // MARK: - Response parsing

    func testParsesValidResponse() {
        let json = """
        {"choices":[{"message":{"content":"Improved text here."}}]}
        """
        let result = parseCompletionResponse(json.data(using: .utf8)!)
        XCTAssertEqual(result.text, "Improved text here.")
        XCTAssertNil(result.error)
    }

    func testTrimsWhitespaceFromContent() {
        let json = """
        {"choices":[{"message":{"content":"  trimmed  \\n"}}]}
        """
        let result = parseCompletionResponse(json.data(using: .utf8)!)
        XCTAssertEqual(result.text, "trimmed")
    }

    func testEmptyContentReturnsError() {
        let json = """
        {"choices":[{"message":{"content":"   "}}]}
        """
        let result = parseCompletionResponse(json.data(using: .utf8)!)
        XCTAssertNil(result.text)
        XCTAssertEqual(result.error, "LLM returned empty response")
    }

    func testMalformedJsonReturnsError() {
        let result = parseCompletionResponse("not json".data(using: .utf8)!)
        XCTAssertNil(result.text)
        XCTAssertEqual(result.error, "Failed to parse LLM response")
    }

    func testMissingChoicesReturnsError() {
        let json = """
        {"model":"test"}
        """
        let result = parseCompletionResponse(json.data(using: .utf8)!)
        XCTAssertNil(result.text)
        XCTAssertEqual(result.error, "Failed to parse LLM response")
    }

    func testEmptyChoicesReturnsError() {
        let json = """
        {"choices":[]}
        """
        let result = parseCompletionResponse(json.data(using: .utf8)!)
        XCTAssertNil(result.text)
        XCTAssertEqual(result.error, "Failed to parse LLM response")
    }

    // MARK: - Error response parsing

    func testParsesErrorResponse() {
        let json = """
        {"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}
        """
        let msg = parseErrorResponse(json.data(using: .utf8)!)
        XCTAssertEqual(msg, "Rate limit exceeded")
    }

    func testReturnsNilForNonErrorResponse() {
        let json = """
        {"choices":[]}
        """
        let msg = parseErrorResponse(json.data(using: .utf8)!)
        XCTAssertNil(msg)
    }
}
