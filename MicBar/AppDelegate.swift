import AppKit
import UserNotifications
import ServiceManagement

private let improveActionID = "IMPROVE_ACTION"
private let copyActionID = "COPY_ACTION"
private let improveCategoryID = "TRANSCRIPTION_WITH_IMPROVE"
private let copyCategoryID = "TRANSCRIPTION_COPY_ONLY"
private let userInfoTextKey = "transcribedText"

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var startItem: NSMenuItem!
    private var stopCopyItem: NSMenuItem!
    private var stopImproveItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private let process = MicToTextProcess()
    private let log = Logger.shared
    private var recordStartTime: Date?
    private var activity: NSObjectProtocol?

    enum State {
        case idle, waiting, recording, processing
    }
    private var state: State = .idle {
        didSet { updateUI() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("=== micbar starting ===")
        log.info("PID=\(ProcessInfo.processInfo.processIdentifier)  PPID=\(getppid())")
        log.info("PATH=\(ProcessInfo.processInfo.environment["PATH"] ?? "<unset>")")

        activity = ProcessInfo.processInfo.beginActivity(
            options: ProcessInfo.ActivityOptions(rawValue: 0x00FFFFFF),
            reason: "Audio recording"
        )

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            self.log.info("notification auth: granted=\(granted) error=\(String(describing: error))")
        }

        let copyAction = UNNotificationAction(identifier: copyActionID, title: "Copy", options: [])
        let improveAction = UNNotificationAction(identifier: improveActionID, title: "Improve", options: [])
        let improveCategory = UNNotificationCategory(identifier: improveCategoryID, actions: [copyAction, improveAction], intentIdentifiers: [])
        let copyCategory = UNNotificationCategory(identifier: copyCategoryID, actions: [copyAction], intentIdentifiers: [])
        center.setNotificationCategories([improveCategory, copyCategory])

        setupStatusItem()
        log.info("MicBar initialized")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon("icon_mic", template: true)

        let menu = NSMenu()
        menu.autoenablesItems = false

        startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "")
        startItem.target = self
        menu.addItem(startItem)

        stopCopyItem = NSMenuItem(title: "Stop -> Clipboard", action: #selector(stopCopy), keyEquivalent: "")
        stopCopyItem.target = self
        stopCopyItem.isEnabled = false
        menu.addItem(stopCopyItem)

        stopImproveItem = NSMenuItem(title: "Stop -> Improve -> Clipboard", action: #selector(stopImprove), keyEquivalent: "")
        stopImproveItem.target = self
        stopImproveItem.isEnabled = false
        menu.addItem(stopImproveItem)

        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setIcon(_ name: String, template: Bool) {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = template
            statusItem.button?.image = image
        }
    }

    private func updateUI() {
        switch state {
        case .idle:
            setIcon("icon_mic", template: true)
            startItem.isEnabled = true
            stopCopyItem.isEnabled = false
            stopImproveItem.isEnabled = false
        case .waiting:
            setIcon("icon_wait", template: true)
            startItem.isEnabled = false
            stopCopyItem.isEnabled = true
            stopImproveItem.isEnabled = true
        case .recording:
            setIcon("icon_rec", template: false)
            startItem.isEnabled = false
            stopCopyItem.isEnabled = true
            stopImproveItem.isEnabled = true
        case .processing:
            setIcon("icon_wait", template: true)
            startItem.isEnabled = false
            stopCopyItem.isEnabled = false
            stopImproveItem.isEnabled = false
        }
    }

    @objc private func startRecording() {
        log.info("start: launching mictotext")
        recordStartTime = Date()

        process.onReady = { [weak self] in
            self?.state = .recording
        }

        if process.start() {
            state = .waiting
        } else {
            log.warning("failed to start mictotext")
            notify(title: "MicBar", body: "Failed to start mictotext")
        }
    }

    @objc private func stopCopy() {
        stopAndFinish(improve: false)
    }

    @objc private func stopImprove() {
        stopAndFinish(improve: true)
    }

    private func stopAndFinish(improve: Bool) {
        state = .processing
        log.info("stop called (improve=\(improve))")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let duration = self.recordStartTime.map { -$0.timeIntervalSinceNow } ?? 0
            self.log.info("recorded \(String(format: "%.1f", duration))s by wall clock")

            guard var text = self.process.stop(), !text.isEmpty else {
                self.log.warning("no text from transcription")
                DispatchQueue.main.async {
                    self.notify(title: "Recording", body: "No speech detected")
                    self.state = .idle
                }
                return
            }

            if improve {
                text = self.improveWriting(text)
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            let preview = text.count > 80 ? String(text.prefix(80)) + "..." : text
            let label = improve ? "Improved & copied to clipboard" : "Copied to clipboard"

            DispatchQueue.main.async {
                self.notify(title: label, body: preview, transcribedText: text, includeImprove: !improve)
                self.log.info("copied to clipboard, notified")
                self.state = .idle
            }
        }
    }

    private func improveWriting(_ text: String) -> String {
        log.info("improve-writing input (\(text.count) chars): \(String(text.prefix(500)))")
        let startTime = Date()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["improve-writing"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
            stdinPipe.fileHandleForWriting.write(text.data(using: .utf8) ?? Data())
            stdinPipe.fileHandleForWriting.closeFile()

            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + 60)
            timer.setEventHandler { [weak proc] in proc?.terminate() }
            timer.resume()

            proc.waitUntilExit()
            timer.cancel()

            let elapsed = -startTime.timeIntervalSinceNow
            log.info("improve-writing rc=\(proc.terminationStatus), took \(String(format: "%.1f", elapsed))s")

            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let stderrStr = String(data: stderrData, encoding: .utf8), !stderrStr.isEmpty {
                log.debug("improve-writing stderr: \(String(stderrStr.prefix(500)))")
            }

            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let improved = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if improved.isEmpty {
                log.warning("improve-writing returned empty, using raw transcription")
                return text
            }
            log.info("improve-writing output (\(improved.count) chars): \(String(improved.prefix(500)))")
            return improved
        } catch {
            log.warning("improve-writing error: \(error)")
            return text
        }
    }

    private func notify(title: String, body: String, transcribedText: String? = nil, includeImprove: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let text = transcribedText {
            content.userInfo = [userInfoTextKey: text]
            content.categoryIdentifier = includeImprove ? improveCategoryID : copyCategoryID
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let text = response.notification.request.content.userInfo[userInfoTextKey] as? String else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case copyActionID:
            log.info("copy from notification (\(text.count) chars)")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            completionHandler()

        case improveActionID:
            log.info("improve from notification (\(text.count) chars)")

            // Re-post the original notification since macOS dismisses it on action tap
            let original = response.notification.request.content
            notify(title: original.title, body: original.body, transcribedText: text)

            state = .processing

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { completionHandler(); return }
                let improved = self.improveWriting(text)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(improved, forType: .string)

                let preview = improved.count > 80 ? String(improved.prefix(80)) + "..." : improved

                DispatchQueue.main.async {
                    self.notify(title: "Improved & copied to clipboard", body: preview, transcribedText: improved)
                    self.log.info("improved from notification, copied to clipboard")
                    self.state = .idle
                    completionHandler()
                }
            }

        default:
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                loginItem.state = .off
                log.info("login item disabled")
            } else {
                try SMAppService.mainApp.register()
                loginItem.state = .on
                log.info("login item enabled")
            }
        } catch {
            log.warning("login item toggle error: \(error)")
        }
    }

    @objc private func quit() {
        if process.isRunning {
            _ = process.stop()
        }
        NSApp.terminate(nil)
    }
}
