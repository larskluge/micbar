import XCTest
import Foundation

// MARK: - Duplicated types from TranscriptionClient.swift (can't import executable target)

private struct TranscriptionResult: Equatable {
    let text: String?
    let error: String?
}

private func parseTranscriptionResponse(data: Data?, response: URLResponse?, error: Error?) -> TranscriptionResult {
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

private func http(_ code: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "http://test")!, statusCode: code, httpVersion: nil, headerFields: nil)!
}

private func jsonData(_ str: String) -> Data {
    str.data(using: .utf8)!
}

// MARK: - Response Parsing: Success

final class TranscriptionParseSuccessTests: XCTestCase {

    func testParsesText() {
        let data = jsonData("{\"text\":\"Hello world\"}")
        let result = parseTranscriptionResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: "Hello world", error: nil))
    }

    func testTrimsWhitespace() {
        let data = jsonData("{\"text\":\"  trimmed  \\n\"}")
        let result = parseTranscriptionResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result.text, "trimmed")
    }

    func testMultilineText() {
        let data = jsonData("{\"text\":\"Line 1.\\nLine 2.\"}")
        let result = parseTranscriptionResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result.text, "Line 1.\nLine 2.")
    }
}

// MARK: - Response Parsing: Empty / Malformed

final class TranscriptionParseErrorTests: XCTestCase {

    func testEmptyTextReturnsError() {
        let data = jsonData("{\"text\":\"   \"}")
        let result = parseTranscriptionResponse(data: data, response: http(200), error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "Transcription returned empty text"))
    }

    func testMalformedJson() {
        let result = parseTranscriptionResponse(data: jsonData("not json"), response: http(200), error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "Failed to parse transcription response"))
    }

    func testMissingTextKey() {
        let result = parseTranscriptionResponse(data: jsonData("{\"model\":\"x\"}"), response: http(200), error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "Failed to parse transcription response"))
    }
}

// MARK: - Response Parsing: Network Errors

final class TranscriptionNetworkErrorTests: XCTestCase {

    func testConnectionRefused() {
        let err = NSError(domain: NSURLErrorDomain, code: -1004, userInfo: nil)
        let result = parseTranscriptionResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "WhisperKit server not running at localhost:50060"))
    }

    func testCannotConnectToHost() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: nil)
        let result = parseTranscriptionResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "WhisperKit server not running at localhost:50060"))
    }

    func testTimeoutError() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                          userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let result = parseTranscriptionResponse(data: nil, response: nil, error: err)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "The request timed out."))
    }

    func testNoResponse() {
        let result = parseTranscriptionResponse(data: nil, response: nil, error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "No response from WhisperKit server"))
    }

    func testNilData() {
        let result = parseTranscriptionResponse(data: nil, response: http(200), error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "Empty response from WhisperKit server"))
    }
}

// MARK: - Response Parsing: HTTP Errors

final class TranscriptionHTTPErrorTests: XCTestCase {

    func testHTTP500() {
        let result = parseTranscriptionResponse(data: jsonData("err"), response: http(500), error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "WhisperKit server returned HTTP 500"))
    }

    func testHTTP400WithJsonError() {
        let data = jsonData("{\"error\":\"Invalid audio format\"}")
        let result = parseTranscriptionResponse(data: data, response: http(400), error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "Invalid audio format"))
    }

    func testHTTP400WithPlainText() {
        let result = parseTranscriptionResponse(data: jsonData("Bad Request"), response: http(400), error: nil)
        XCTAssertEqual(result, TranscriptionResult(text: nil, error: "WhisperKit server returned HTTP 400"))
    }
}
