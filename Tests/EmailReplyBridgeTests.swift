import XCTest
import Foundation

// MARK: - Mirrors EmailReplyBridge.swift pure logic
//
// The executable target can't be imported into tests, so the pure helpers are
// duplicated here (same convention as OllamaCallTests). KEEP IN SYNC with
// MicBar/EmailReplyBridge.swift — these are the executable spec for that logic.

private struct GmailThread: Equatable {
    let url: String
    let subject: String
}

/// Gmail tab title is "<subject> - <account email> - <org> Mail". Take everything
/// before the first " - "-separated component that contains an email address.
private func subject(fromTitle title: String) -> String? {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let parts = trimmed.components(separatedBy: " - ")
    guard let emailIndex = parts.firstIndex(where: { $0.contains("@") }), emailIndex >= 1 else {
        return nil
    }
    let subject = parts[0..<emailIndex].joined(separator: " - ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return subject.isEmpty ? nil : subject
}

/// The last fragment segment when it looks like a Gmail thread/message id
/// (a long alphanumeric token, e.g. FMfcgz…), else nil for list views like #inbox.
private func threadId(inURL url: String) -> String? {
    guard let hashIndex = url.firstIndex(of: "#") else { return nil }
    let fragment = url[url.index(after: hashIndex)...]
    let segments = fragment.split(separator: "/").map(String.init)
    guard segments.count >= 2, let last = segments.last else { return nil }
    let isIdLike = last.count >= 12 && last.allSatisfy { $0.isLetter || $0.isNumber }
    return isIdLike ? last : nil
}

/// Parses the AppleScript output (one "url\ttitle" line per Gmail window, frontmost first).
private func parseGmailLines(_ output: String) -> [GmailThread] {
    output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
        let cols = String(line).components(separatedBy: "\t")
        guard cols.count >= 2, !cols[0].isEmpty else { return nil }
        return GmailThread(url: cols[0], subject: subject(fromTitle: cols[1]) ?? "")
    }
}

/// The frontmost window showing an open thread, or nil if only list views are open.
private func selectThread(from threads: [GmailThread]) -> GmailThread? {
    threads.first(where: { threadId(inURL: $0.url) != nil })
}

private func composePrompt(url: String, subject: String, transcript: String) -> String {
    """
    Draft a reply to the Gmail thread below and SAVE IT AS A DRAFT in that thread — do NOT send. Write it in my voice, replying to the latest message in the thread.

    Thread:  \(url)
    Subject: \(subject)

    My raw spoken notes for the reply (clean these up into a proper email):
    \(transcript)
    """
}

// MARK: - Subject parsing

final class SubjectFromTitleTests: XCTestCase {

    func testWorkspaceTitle() {
        XCTAssertEqual(
            subject(fromTitle: "Boro.Today LiteDeck - me@aekym.com - aekym.com Mail"),
            "Boro.Today LiteDeck")
    }

    func testSubjectContainingSeparator() {
        XCTAssertEqual(
            subject(fromTitle: "Re: Foo - Bar - me@aekym.com - aekym.com Mail"),
            "Re: Foo - Bar")
    }

    func testConsumerGmailTitle() {
        XCTAssertEqual(
            subject(fromTitle: "Weekend plans - someone@gmail.com - Gmail"),
            "Weekend plans")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(
            subject(fromTitle: "  Hello  - me@aekym.com - aekym.com Mail"),
            "Hello")
    }

    func testEmptyTitleIsNil() {
        XCTAssertNil(subject(fromTitle: ""))
    }

    func testTitleWithoutEmailIsNil() {
        XCTAssertNil(subject(fromTitle: "Just a window title"))
    }
}

// MARK: - Thread id detection

final class ThreadIdTests: XCTestCase {

    private let id = "FMfcgzQbgPZxKpGqVmZjNcLtRbWdScHk"

    func testInboxThreadHasId() {
        XCTAssertEqual(
            threadId(inURL: "https://mail.google.com/mail/u/0/#inbox/\(id)"),
            id)
    }

    func testBareInboxHasNoId() {
        XCTAssertNil(threadId(inURL: "https://mail.google.com/mail/u/0/#inbox"))
    }

    func testShortSearchTermIsNotId() {
        XCTAssertNil(threadId(inURL: "https://mail.google.com/mail/u/0/#search/invoice"))
    }

    func testLabelThreadUsesLastSegment() {
        XCTAssertEqual(
            threadId(inURL: "https://mail.google.com/mail/u/0/#label/Work/\(id)"),
            id)
    }

    func testTooShortLastSegmentIsNotId() {
        XCTAssertNil(threadId(inURL: "https://mail.google.com/mail/u/0/#inbox/abc"))
    }

    func testNoFragmentHasNoId() {
        XCTAssertNil(threadId(inURL: "https://mail.google.com/mail/u/0/"))
    }
}

// MARK: - Parsing AppleScript output

final class ParseGmailLinesTests: XCTestCase {

    func testParsesUrlAndSubjectPerLine() {
        let out = """
        https://mail.google.com/mail/u/0/#inbox/FMfcgzQbgPZxKpGqVmZjNcLtRbWdScHk\tProject sync - me@aekym.com - aekym.com Mail
        https://mail.google.com/mail/u/0/#inbox\tInbox - me@aekym.com - aekym.com Mail

        """
        let threads = parseGmailLines(out)
        XCTAssertEqual(threads, [
            GmailThread(url: "https://mail.google.com/mail/u/0/#inbox/FMfcgzQbgPZxKpGqVmZjNcLtRbWdScHk",
                        subject: "Project sync"),
            GmailThread(url: "https://mail.google.com/mail/u/0/#inbox", subject: "Inbox"),
        ])
    }

    func testSkipsMalformedLines() {
        let threads = parseGmailLines("no-tab-here\n\thttps-missing-url\n")
        XCTAssertEqual(threads, [])
    }

    func testEmptyOutputIsEmpty() {
        XCTAssertEqual(parseGmailLines(""), [])
    }
}

// MARK: - Selecting the active thread

final class SelectThreadTests: XCTestCase {

    private let id = "FMfcgzQbgPZxKpGqVmZjNcLtRbWdScHk"
    private func thread(_ frag: String, _ subj: String = "S") -> GmailThread {
        GmailThread(url: "https://mail.google.com/mail/u/0/#\(frag)", subject: subj)
    }

    func testNoWindowsIsNil() {
        XCTAssertNil(selectThread(from: []))
    }

    func testBareInboxOnlyIsNil() {
        XCTAssertNil(selectThread(from: [thread("inbox")]))
    }

    func testSingleThreadSelected() {
        let t = thread("inbox/\(id)")
        XCTAssertEqual(selectThread(from: [t]), t)
    }

    func testPrefersThreadOverBareInbox() {
        let open = thread("inbox/\(id)")
        XCTAssertEqual(selectThread(from: [thread("inbox"), open]), open)
    }

    func testPrefersFrontmostThread() {
        let front = thread("inbox/\(id)", "Front")
        let back = thread("label/x/\(id)", "Back")
        XCTAssertEqual(selectThread(from: [front, back]), front)
    }
}

// MARK: - Prompt composition

final class ComposePromptTests: XCTestCase {

    func testProducesExpectedPrompt() {
        let prompt = composePrompt(
            url: "https://mail.google.com/mail/u/0/#inbox/FMfcgz",
            subject: "Project sync",
            transcript: "tell them yes ship it friday")
        XCTAssertEqual(prompt, """
        Draft a reply to the Gmail thread below and SAVE IT AS A DRAFT in that thread — do NOT send. Write it in my voice, replying to the latest message in the thread.

        Thread:  https://mail.google.com/mail/u/0/#inbox/FMfcgz
        Subject: Project sync

        My raw spoken notes for the reply (clean these up into a proper email):
        tell them yes ship it friday
        """)
    }
}
