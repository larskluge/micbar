import AppKit
import UserNotifications
import ServiceManagement

private let improveActionID = "IMPROVE_ACTION"
private let copyActionID = "COPY_ACTION"
private let improveCategoryID = "TRANSCRIPTION_WITH_IMPROVE"
private let copyCategoryID = "TRANSCRIPTION_COPY_ONLY"
private let userInfoTextKey = "transcribedText"

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, RecordingPopoverDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var popoverController: RecordingPopoverController!
    private var eventMonitor: Any?

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

        popoverController = RecordingPopoverController()
        popoverController.delegate = self
        popoverController.onSizeChange = { [weak self] size in
            self?.popover.contentSize = size
        }

        popover.contentViewController = popoverController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            popoverController.updateState(mapState(state))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func mapState(_ s: State) -> RecordingPopoverController.AppDelegateState {
        switch s {
        case .idle: return .idle
        case .waiting: return .waiting
        case .recording: return .recording
        case .processing: return .processing
        }
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
        case .waiting:
            setIcon("icon_wait", template: true)
        case .recording:
            setIcon("icon_rec", template: false)
        case .processing:
            setIcon("icon_wait", template: true)
        }
        popoverController?.updateState(mapState(state))
    }

    // MARK: - RecordingPopoverDelegate

    var isLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func popoverDidRequestStart() {
        startRecording()
    }

    func popoverDidRequestStopCopy() {
        stopAndFinish(improve: false)
    }

    func popoverDidRequestStopImprove() {
        stopAndFinish(improve: true)
    }

    func popoverDidRequestCancel() {
        cancelRecording()
    }

    func popoverDidRequestToggleLogin() {
        toggleLogin()
    }

    func popoverDidRequestQuit() {
        quit()
    }

    // MARK: - Recording

    private func startRecording() {
        log.info("start: launching mictotext")
        recordStartTime = Date()
        popoverController.setRecordingStartTime(recordStartTime!)

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

    private func cancelRecording() {
        log.info("cancel: discarding recording")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            _ = self.process.stop()
            DispatchQueue.main.async {
                self.popover.performClose(nil)
                self.state = .idle
                self.log.info("recording discarded")
            }
        }
        state = .processing // show spinner while stopping
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
                self.popover.performClose(nil)
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

        var environment = ProcessInfo.processInfo.environment
        if let path = environment["PATH"], !path.contains("/opt/homebrew/bin") {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        proc.environment = environment

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

    // MARK: - NSPopoverDelegate

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        // Don't allow click-outside dismissal while recording or waiting
        return state == .idle || state == .processing
    }

    private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                log.info("login item disabled")
            } else {
                try SMAppService.mainApp.register()
                log.info("login item enabled")
            }
        } catch {
            log.warning("login item toggle error: \(error)")
        }
    }

    private func quit() {
        if process.isRunning {
            _ = process.stop()
        }
        NSApp.terminate(nil)
    }
}
