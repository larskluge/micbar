import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, RecordingPopoverDelegate, AnswerPopoverDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var popoverController: RecordingPopoverController!
    private let answerPopover = NSPopover()
    private var answerPopoverController: AnswerPopoverController!

    private let recorder = Recorder()
    private let log = Logger.shared
    private var recordStartTime: Date?
    private var activity: NSObjectProtocol?

    let transcriptStore = TranscriptStore()
    private lazy var historyWindowController = HistoryWindowController(
        store: transcriptStore,
        onRecord: { [weak self] in self?.startRecording(showPopover: false) },
        onStop: { [weak self] in self?.stopAndFinish(mode: .copy) }
    )

    enum State {
        case idle, waiting, recording, processing
    }
    private var state: State = .idle {
        didSet { updateUI() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if recorder.isRunning {
            log.info("app terminating, killing recording")
            recorder.forceKill()
        }
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

        answerPopoverController = AnswerPopoverController()
        answerPopoverController.delegate = self
        answerPopoverController.onSizeChange = { [weak self] size in
            self?.answerPopover.contentSize = size
        }
        answerPopover.contentViewController = answerPopoverController
        answerPopover.behavior = .transient
        answerPopover.animates = true

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            historyWindowController.showWindow()
        } else {
            handleLeftClick()
        }
    }

    private func handleLeftClick() {
        switch state {
        case .idle:
            startRecording()
        case .waiting:
            break
        case .recording:
            if popover.isShown {
                popover.performClose(nil)
            } else {
                showPopover()
            }
        case .processing:
            break
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popoverController.updateState(mapState(state))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
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
        switch state {
        case .idle: transcriptStore.recordingState = .idle
        case .waiting: transcriptStore.recordingState = .waiting
        case .recording: transcriptStore.recordingState = .recording
        case .processing: transcriptStore.recordingState = .processing
        }
    }

    // MARK: - RecordingPopoverDelegate

    func popoverDidRequestStopCopy() {
        stopAndFinish(mode: .copy)
    }

    func popoverDidRequestStopImprove() {
        stopAndFinish(mode: .improve)
    }

    func popoverDidRequestStopAnswer() {
        stopAndAnswer()
    }

    func popoverDidRequestCancel() {
        cancelRecording()
    }

    func popoverDidRequestOpenSettings() {
        cancelRecording()
        historyWindowController.showWindow(tab: 1)
    }

    // MARK: - Recording

    private func startRecording(showPopover: Bool = true) {
        guard state == .idle else {
            log.info("start: ignored, state=\(state)")
            return
        }
        log.info("start: beginning recording")
        recordStartTime = Date()
        popoverController.setRecordingStartTime(recordStartTime!)

        recorder.onReady = { [weak self] in
            self?.state = .recording
        }

        if recorder.start() {
            state = .waiting
            if showPopover {
                self.showPopover()
            }
        } else {
            log.warning("failed to start recording")
            notify(title: "MicBar", body: "Failed to start recording")
        }
    }

    private func cancelRecording() {
        log.info("cancel: discarding recording")
        recorder.forceKill()
        state = .idle
        popover.performClose(nil)
    }

    private enum FinishMode {
        case copy, improve, answer
    }

    private func stopAndFinish(mode: FinishMode) {
        state = .processing
        log.info("stop called (mode=\(mode))")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let duration = self.recordStartTime.map { -$0.timeIntervalSinceNow } ?? 0
            self.log.info("recorded \(String(format: "%.1f", duration))s by wall clock")

            guard var text = self.recorder.stop(), !text.isEmpty else {
                self.log.warning("no text from transcription")
                DispatchQueue.main.async {
                    self.notify(title: "Recording", body: "No speech detected")
                    self.state = .idle
                }
                return
            }

            let rawText = text
            var llmFailed = false
            var llmError: String?
            var improvedText: String?
            var answerText: String?

            switch mode {
            case .copy:
                break
            case .improve:
                let result = runImproveWriting(text)
                if let improved = result.text {
                    text = improved
                    improvedText = improved
                } else {
                    llmFailed = true
                    llmError = result.error
                }
            case .answer:
                let result = runAnswerQuestion(text)
                if let answer = result.text {
                    text = answer
                    answerText = answer
                } else {
                    llmFailed = true
                    llmError = result.error
                }
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            let preview = text.count > 80 ? String(text.prefix(80)) + "..." : text
            let label: String
            if llmFailed {
                switch mode {
                case .improve: label = "Improve failed — raw transcript copied"
                case .answer: label = "Answer failed — raw transcript copied"
                case .copy: label = "Copied to clipboard"
                }
            } else {
                switch mode {
                case .copy: label = "Copied to clipboard"
                case .improve: label = "Improved & copied to clipboard"
                case .answer: label = "Answer copied to clipboard"
                }
            }

            DispatchQueue.main.async {
                self.transcriptStore.addTranscript(
                    raw: rawText, improved: improvedText,
                    improveError: mode == .improve ? llmError : nil,
                    answer: answerText,
                    answerError: mode == .answer ? llmError : nil
                )
                self.popover.performClose(nil)
                self.notify(title: label, body: preview)
                self.log.info("copied to clipboard, notified")
                self.state = .idle
            }
        }
    }

    private func stopAndAnswer() {
        state = .processing
        log.info("stop called (mode=answer)")

        // Close recording popover, open answer popover with spinner
        popover.performClose(nil)
        showAnswerPopover()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let duration = self.recordStartTime.map { -$0.timeIntervalSinceNow } ?? 0
            self.log.info("recorded \(String(format: "%.1f", duration))s by wall clock")

            guard let rawText = self.recorder.stop(), !rawText.isEmpty else {
                self.log.warning("no text from transcription")
                DispatchQueue.main.async {
                    self.answerPopover.performClose(nil)
                    self.notify(title: "Recording", body: "No speech detected")
                    self.state = .idle
                }
                return
            }

            let result = runAnswerQuestion(rawText)

            DispatchQueue.main.async {
                self.transcriptStore.addTranscript(
                    raw: rawText, improved: nil,
                    answer: result.text,
                    answerError: result.error
                )

                if let answer = result.text {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                }

                self.answerPopoverController.showAnswer(text: result.text ?? "", error: result.error)
                self.state = .idle
            }
        }
    }

    private func showAnswerPopover() {
        guard let button = statusItem.button else { return }
        answerPopoverController.showSpinner()
        answerPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        answerPopover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - AnswerPopoverDelegate

    func answerPopoverDidRequestClose() {
        answerPopover.performClose(nil)
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let id = UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        historyWindowController.showWindow()
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - NSPopoverDelegate

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        // Don't allow click-outside dismissal while recording or waiting
        // Allow closing when idle (answered state sets idle), or processing
        return state == .idle || state == .processing
    }

}
