import Foundation

/// Bridges a transcript into a Gmail draft: reads the open Gmail thread from
/// Chrome, composes a prompt, and hands it to Kubera (a Telegram bot) via the
/// local `tg` userbot. Kubera drafts the threaded reply and saves it as a draft.
///
/// The pure helpers (`subject(fromTitle:)`, `threadId(inURL:)`, `composePrompt`,
/// `selectThread`, `parseGmailLines`) are mirrored in EmailReplyBridgeTests.swift —
/// keep the two in sync.
enum EmailReplyBridge {

    struct GmailThread: Equatable {
        let url: String
        let subject: String
    }

    /// A user-facing failure reason (no open thread, `tg` failure, …).
    struct Failure: Error {
        let message: String
    }

    /// Path to the local, authenticated `tg` userbot binary.
    static let tgPath = "/Users/l/bin/tg"
    /// Kubera's Telegram @username (the DM target).
    static let kuberaUsername = "@kuberamarbot"

    // MARK: - High-level flow

    /// Reads the open Gmail thread, composes the prompt, and sends it to Kubera.
    /// Blocks the calling thread (AppleScript + `tg`); call off the main queue.
    /// Returns the resolved thread on success, or a user-facing error message.
    static func draftReply(transcript: String, log: Logger = .shared) -> Result<GmailThread, Failure> {
        let thread: GmailThread
        switch readOpenGmailThread() {
        case .chromeUnreadable:
            log.warning("email reply: couldn't read Chrome (Automation permission?)")
            return .failure(Failure(message: "Couldn't read Chrome. Allow MicBar to control Google Chrome in System Settings → Privacy & Security → Automation, then try again."))
        case .noThreadOpen:
            log.warning("email reply: no open Gmail thread")
            return .failure(Failure(message: "No open email thread. Open a Gmail thread in Chrome and try again."))
        case .thread(let found):
            thread = found
        }
        log.info("email reply: thread \"\(thread.subject)\" — \(thread.url)")
        let prompt = composePrompt(url: thread.url, subject: thread.subject, transcript: transcript)
        switch send(prompt: prompt, log: log) {
        case .success:
            log.info("email reply: prompt sent to Kubera")
            return .success(thread)
        case .failure(let error):
            log.warning("email reply: tg send failed — \(error.message)")
            return .failure(error)
        }
    }

    // MARK: - Pure logic (mirrored in tests)

    /// Gmail tab title is "<subject> - <account email> - <org> Mail". Take everything
    /// before the first " - "-separated component that contains an email address.
    static func subject(fromTitle title: String) -> String? {
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
    static func threadId(inURL url: String) -> String? {
        guard let hashIndex = url.firstIndex(of: "#") else { return nil }
        let fragment = url[url.index(after: hashIndex)...]
        let segments = fragment.split(separator: "/").map(String.init)
        guard segments.count >= 2, let last = segments.last else { return nil }
        let isIdLike = last.count >= 12 && last.allSatisfy { $0.isLetter || $0.isNumber }
        return isIdLike ? last : nil
    }

    /// Parses the AppleScript output (one "url\ttitle" line per Gmail window, frontmost first).
    static func parseGmailLines(_ output: String) -> [GmailThread] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let cols = String(line).components(separatedBy: "\t")
            guard cols.count >= 2, !cols[0].isEmpty else { return nil }
            return GmailThread(url: cols[0], subject: subject(fromTitle: cols[1]) ?? "")
        }
    }

    /// The frontmost window showing an open thread, or nil if only list views are open.
    static func selectThread(from threads: [GmailThread]) -> GmailThread? {
        threads.first(where: { threadId(inURL: $0.url) != nil })
    }

    static func composePrompt(url: String, subject: String, transcript: String) -> String {
        """
        Draft a reply to the Gmail thread below and SAVE IT AS A DRAFT in that thread — do NOT send. Write it in my voice, replying to the latest message in the thread.

        Thread:  \(url)
        Subject: \(subject)

        My raw spoken notes for the reply (clean these up into a proper email):
        \(transcript)
        """
    }

    // MARK: - Side effects

    // `TB`/`LF` are bound to the AppleScript `tab`/`linefeed` constants *outside* the
    // `tell` block: inside it, `tab` resolves to Chrome's tab-element terminology, not
    // an ASCII tab, which would corrupt the delimiter the parser splits on.
    private static let readThreadsScript = """
    set TB to tab
    set LF to linefeed
    set out to ""
    tell application "Google Chrome"
      repeat with w in windows
        set t to active tab of w
        set u to URL of t
        if u starts with "https://mail.google.com/" then
          set out to out & u & TB & (title of t) & LF
        end if
      end repeat
    end tell
    return out
    """

    /// Outcome of reading Chrome: a thread, no thread open, or Chrome was unreadable
    /// (osascript failed — most often a missing Automation permission).
    enum ThreadReadOutcome {
        case thread(GmailThread)
        case noThreadOpen
        case chromeUnreadable
    }

    /// Reads the frontmost open Gmail thread from Chrome via AppleScript.
    static func readOpenGmailThread(runScript: (String) -> String? = runAppleScript) -> ThreadReadOutcome {
        guard let output = runScript(readThreadsScript) else { return .chromeUnreadable }
        let threads = parseGmailLines(output)
        Logger.shared.info("email reply: parsed \(threads.count) Gmail window(s)")
        if let selected = selectThread(from: threads) { return .thread(selected) }
        return .noThreadOpen
    }

    /// Runs an AppleScript via `osascript` and returns stdout, or nil on failure.
    static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            Logger.shared.warning("osascript launch failed: \(error.localizedDescription)")
            return nil
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Logger.shared.info("osascript exit=\(process.terminationStatus) stdout=\(out.count)B stderr=\(err.isEmpty ? "<none>" : err)")
        guard process.terminationStatus == 0 else { return nil }
        return out
    }

    /// Sends the prompt to Kubera via `tg send --to <username>`, piping the prompt
    /// through stdin so there is no shell and no quoting of its newlines/quotes.
    static func send(prompt: String, tgPath: String = tgPath, log: Logger = .shared) -> Result<Void, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tgPath)
        process.arguments = ["send", "--to", kuberaUsername]
        let stdin = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failure(Failure(message: "Couldn't launch tg: \(error.localizedDescription)"))
        }

        if let data = prompt.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return .success(())
        }
        let errMsg = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .failure(Failure(message: errMsg.isEmpty ? "tg exited with code \(process.terminationStatus)" : errMsg))
    }
}
