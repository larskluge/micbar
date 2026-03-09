import AppKit
import QuartzCore

protocol RecordingPopoverDelegate: AnyObject {
    func popoverDidRequestStart()
    func popoverDidRequestStopCopy()
    func popoverDidRequestStopImprove()
    func popoverDidRequestCancel()
    func popoverDidRequestToggleLogin()
    func popoverDidRequestQuit()
    var isLoginEnabled: Bool { get }
}

class RecordingPopoverController: NSViewController {
    weak var delegate: RecordingPopoverDelegate?

    private var idleView: NSView!
    private var recordingView: NSView!
    private var processingView: NSView!

    private var timerLabel: NSTextField!
    private var redDot: NSView!
    private var redDotGlow: NSView!
    private var loginCheckbox: NSButton!

    private var displayTimer: Timer?
    private var recordingStartTime: Date?
    private var pulseAnimation: Timer?

    private let W: CGFloat = 280

    private var currentState: AppDelegateState = .idle

    enum AppDelegateState {
        case idle, waiting, recording, processing
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 200))
        view.wantsLayer = true

        buildIdleView()
        buildRecordingView()
        buildProcessingView()

        showState(.idle)
    }

    func updateState(_ state: AppDelegateState) {
        currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.showState(state)
        }
    }

    func setRecordingStartTime(_ date: Date) {
        recordingStartTime = date
    }

    private func showState(_ state: AppDelegateState) {
        idleView.isHidden = true
        recordingView.isHidden = true
        processingView.isHidden = true
        stopTimer()
        stopPulse()

        switch state {
        case .idle:
            idleView.isHidden = false
            loginCheckbox.state = delegate?.isLoginEnabled == true ? .on : .off
            setViewHeight(idleView)
        case .waiting:
            recordingView.isHidden = false
            timerLabel.stringValue = "Starting..."
            setViewHeight(recordingView)
        case .recording:
            recordingView.isHidden = false
            startTimer()
            startPulse()
            setViewHeight(recordingView)
        case .processing:
            processingView.isHidden = false
            setViewHeight(processingView)
        }
    }

    private func setViewHeight(_ activeView: NSView) {
        let h = activeView.frame.height
        view.frame.size.height = h
        preferredContentSize = NSSize(width: W, height: h)
    }

    // MARK: - Idle View

    private func buildIdleView() {
        let pad: CGFloat = 16
        let btnH: CGFloat = 44
        let footerH: CGFloat = 28
        let sepGap: CGFloat = 14
        let totalH: CGFloat = pad + footerH + sepGap + 1 + sepGap + btnH + pad

        idleView = NSView(frame: NSRect(x: 0, y: 0, width: W, height: totalH))
        idleView.wantsLayer = true

        var y = pad

        // Footer row: Login checkbox left, Quit right
        loginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(loginClicked))
        loginCheckbox.frame = NSRect(x: pad, y: y, width: 150, height: footerH)
        loginCheckbox.controlSize = .regular
        loginCheckbox.font = .systemFont(ofSize: 12)

        let quitButton = NSButton(frame: NSRect(x: W - pad - 44, y: y, width: 44, height: footerH))
        quitButton.title = "Quit"
        quitButton.bezelStyle = .recessed
        quitButton.target = self
        quitButton.action = #selector(quitClicked)
        quitButton.controlSize = .small
        quitButton.font = .systemFont(ofSize: 12)
        quitButton.contentTintColor = .secondaryLabelColor

        y += footerH + sepGap

        let separator = NSBox(frame: NSRect(x: pad, y: y, width: W - pad * 2, height: 1))
        separator.boxType = .separator
        y += 1 + sepGap

        // Start Recording button — red accent
        let startButton = NSButton(frame: NSRect(x: pad, y: y, width: W - pad * 2, height: btnH))
        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.target = self
        startButton.action = #selector(startClicked)
        startButton.keyEquivalent = "\r"
        startButton.contentTintColor = .white
        startButton.bezelColor = NSColor.systemRed

        if let micImg = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = micImg
            let attrStr = NSMutableAttributedString(attachment: attachment)
            attrStr.append(NSAttributedString(string: " Start Recording"))
            attrStr.addAttributes([
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ], range: NSRange(location: 0, length: attrStr.length))
            startButton.attributedTitle = attrStr
        } else {
            startButton.title = "Start Recording"
            startButton.font = .systemFont(ofSize: 14, weight: .semibold)
        }

        idleView.addSubview(startButton)
        idleView.addSubview(separator)
        idleView.addSubview(loginCheckbox)
        idleView.addSubview(quitButton)

        view.addSubview(idleView)
    }

    // MARK: - Recording View

    private func buildRecordingView() {
        let pad: CGFloat = 16
        let btnH: CGFloat = 36
        let btnGap: CGFloat = 8
        let statusH: CGFloat = 20
        let topGap: CGFloat = 14
        let cancelH: CGFloat = 20
        let cancelGap: CGFloat = 6
        let totalH: CGFloat = pad + cancelH + cancelGap + btnH + btnGap + btnH + topGap + statusH + pad

        recordingView = NSView(frame: NSRect(x: 0, y: 0, width: W, height: totalH))
        recordingView.wantsLayer = true

        var y = pad

        // Cancel link at bottom
        let cancelButton = NSButton(frame: NSRect(x: pad, y: y, width: W - pad * 2, height: cancelH))
        cancelButton.title = "Cancel Recording"
        cancelButton.bezelStyle = .recessed
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.controlSize = .small
        cancelButton.font = .systemFont(ofSize: 11)
        cancelButton.contentTintColor = .secondaryLabelColor
        cancelButton.keyEquivalent = "\u{1b}" // Escape key
        y += cancelH + cancelGap

        // Secondary button
        let stopImproveButton = makeButton(
            title: "Stop, Improve & Copy",
            action: #selector(stopImproveClicked),
            isPrimary: false,
            icon: "sparkles",
            shortcut: "\u{2318}I"
        )
        stopImproveButton.frame = NSRect(x: pad, y: y, width: W - pad * 2, height: btnH)
        y += btnH + btnGap

        // Primary button
        let stopCopyButton = makeButton(
            title: "Stop & Copy",
            action: #selector(stopCopyClicked),
            isPrimary: true,
            icon: "stop.circle.fill",
            shortcut: "\u{2318}C"
        )
        stopCopyButton.frame = NSRect(x: pad, y: y, width: W - pad * 2, height: btnH)
        y += btnH + topGap

        // Status row: red dot + "Recording" left, timer right
        let dotSize: CGFloat = 10
        let glowSize: CGFloat = 18
        let dotX: CGFloat = pad
        let dotCenterY = y + statusH / 2

        redDotGlow = NSView(frame: NSRect(
            x: dotX - (glowSize - dotSize) / 2,
            y: dotCenterY - glowSize / 2,
            width: glowSize, height: glowSize
        ))
        redDotGlow.wantsLayer = true
        redDotGlow.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.25).cgColor
        redDotGlow.layer?.cornerRadius = glowSize / 2

        redDot = NSView(frame: NSRect(
            x: dotX, y: dotCenterY - dotSize / 2,
            width: dotSize, height: dotSize
        ))
        redDot.wantsLayer = true
        redDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        redDot.layer?.cornerRadius = dotSize / 2

        let labelX = dotX + glowSize + 4
        let recordingLabel = NSTextField(labelWithString: "Recording")
        recordingLabel.frame = NSRect(x: labelX, y: y, width: 100, height: statusH)
        recordingLabel.font = .systemFont(ofSize: 13, weight: .medium)
        recordingLabel.textColor = .labelColor

        timerLabel = NSTextField(labelWithString: "0:00")
        timerLabel.frame = NSRect(x: W - pad - 80, y: y, width: 80, height: statusH)
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timerLabel.textColor = .secondaryLabelColor
        timerLabel.alignment = .right

        recordingView.addSubview(redDotGlow)
        recordingView.addSubview(redDot)
        recordingView.addSubview(recordingLabel)
        recordingView.addSubview(timerLabel)
        recordingView.addSubview(stopCopyButton)
        recordingView.addSubview(stopImproveButton)
        recordingView.addSubview(cancelButton)

        view.addSubview(recordingView)
    }

    // MARK: - Processing View

    private func buildProcessingView() {
        processingView = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 90))
        processingView.wantsLayer = true

        let spinner = NSProgressIndicator(frame: NSRect(x: (W - 20) / 2, y: 46, width: 20, height: 20))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "Processing...")
        label.frame = NSRect(x: 0, y: 16, width: W, height: 20)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        processingView.addSubview(spinner)
        processingView.addSubview(label)

        view.addSubview(processingView)
    }

    // MARK: - Helpers

    private func makeButton(title: String, action: Selector, isPrimary: Bool, icon: String? = nil, shortcut: String? = nil) -> NSButton {
        let button = NSButton(frame: .zero)
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .large

        let weight: NSFont.Weight = isPrimary ? .semibold : .regular
        let primaryColor = isPrimary ? NSColor.white : NSColor.labelColor
        let hintColor = isPrimary ? NSColor.white.withAlphaComponent(0.6) : NSColor.tertiaryLabelColor

        let attrStr = NSMutableAttributedString()

        if let iconName = icon,
           let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let attachment = NSTextAttachment()
            attachment.image = img
            attrStr.append(NSAttributedString(attachment: attachment))
            attrStr.append(NSAttributedString(string: " "))
        }

        let titlePart = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: weight),
            .foregroundColor: primaryColor
        ])
        attrStr.append(titlePart)

        if let sc = shortcut {
            let hintPart = NSAttributedString(string: "  \(sc)", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: hintColor
            ])
            attrStr.append(hintPart)
        }

        // Apply base font to icon attachment range too
        if attrStr.length > 0 {
            attrStr.addAttributes([
                .font: NSFont.systemFont(ofSize: 13, weight: weight),
                .foregroundColor: primaryColor
            ], range: NSRange(location: 0, length: min(2, attrStr.length)))
        }

        button.attributedTitle = attrStr

        if isPrimary {
            button.keyEquivalent = "\r"
            button.contentTintColor = .white
            button.bezelColor = .controlAccentColor
        }

        return button
    }

    // MARK: - Timer

    private func startTimer() {
        updateTimerDisplay()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimerDisplay()
        }
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func updateTimerDisplay() {
        guard let start = recordingStartTime else {
            timerLabel?.stringValue = "0:00"
            return
        }
        let elapsed = Int(-start.timeIntervalSinceNow)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        timerLabel?.stringValue = String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Pulse Animation

    private func startPulse() {
        var glowVisible = true
        pulseAnimation = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                self.redDotGlow.animator().alphaValue = glowVisible ? 0.2 : 1.0
                self.redDot.animator().alphaValue = glowVisible ? 0.5 : 1.0
            }
            glowVisible.toggle()
        }
    }

    private func stopPulse() {
        pulseAnimation?.invalidate()
        pulseAnimation = nil
        redDotGlow?.alphaValue = 1.0
        redDot?.alphaValue = 1.0
    }

    // MARK: - Actions

    @objc private func startClicked() {
        delegate?.popoverDidRequestStart()
    }

    @objc private func stopCopyClicked() {
        delegate?.popoverDidRequestStopCopy()
    }

    @objc private func stopImproveClicked() {
        delegate?.popoverDidRequestStopImprove()
    }

    @objc private func cancelClicked() {
        delegate?.popoverDidRequestCancel()
    }

    @objc private func loginClicked() {
        delegate?.popoverDidRequestToggleLogin()
    }

    @objc private func quitClicked() {
        delegate?.popoverDidRequestQuit()
    }
}
