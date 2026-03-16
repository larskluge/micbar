import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, RecordingPopoverDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var popoverController: RecordingPopoverController!

    private let process = MicToTextProcess()
    private let log = Logger.shared
    private var recordStartTime: Date?
    private var activity: NSObjectProtocol?

    let transcriptStore = TranscriptStore()
    private lazy var historyWindowController = HistoryWindowController(
        store: transcriptStore,
        onRecord: { [weak self] in self?.startRecording() },
        onStop: { [weak self] in self?.stopAndFinish(improve: false) }
    )

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
        stopAndFinish(improve: false)
    }

    func popoverDidRequestStopImprove() {
        stopAndFinish(improve: true)
    }

    func popoverDidRequestCancel() {
        cancelRecording()
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
            showPopover()
        } else {
            log.warning("failed to start mictotext")
            notify(title: "MicBar", body: "Failed to start mictotext")
        }
    }

    private func cancelRecording() {
        log.info("cancel: discarding recording")
        process.forceKill()
        popover.performClose(nil)
        state = .idle
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

            let rawText = text
            var improveFailed = false
            if improve {
                if let improved = self.improveWriting(text) {
                    text = improved
                } else {
                    improveFailed = true
                }
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            let preview = text.count > 80 ? String(text.prefix(80)) + "..." : text
            let label: String
            if improveFailed {
                label = "Improve failed — raw transcript copied"
            } else if improve {
                label = "Improved & copied to clipboard"
            } else {
                label = "Copied to clipboard"
            }

            let improvedText = (improve && !improveFailed) ? text : nil

            DispatchQueue.main.async {
                self.transcriptStore.addTranscript(raw: rawText, improved: improvedText)
                self.popover.performClose(nil)
                self.notify(title: label, body: preview)
                self.log.info("copied to clipboard, notified")
                self.state = .idle
            }
        }
    }

    private func improveWriting(_ text: String) -> String? {
        runImproveWriting(text, log: log)
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
        return state == .idle || state == .processing
    }

}
