import AppKit
import QuartzCore

protocol RecordingPopoverDelegate: AnyObject {
    func popoverDidRequestStart()
    func popoverDidRequestStopCopy()
    func popoverDidRequestStopImprove()
    func popoverDidRequestCancel()
    func popoverDidRequestShowHistory()
    func popoverDidRequestQuit()
}

class RecordingPopoverController: NSViewController {
    weak var delegate: RecordingPopoverDelegate?

    private var idleView: NSView!
    private var recordingView: NSView!
    private var processingView: NSView!

    private var timerLabel: NSTextField!
    private var redDot: NSView!
    private var redDotGlow: NSView!

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
            // idle view shown
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

    var onSizeChange: ((NSSize) -> Void)?

    private func setViewHeight(_ activeView: NSView) {
        let size = NSSize(width: W, height: activeView.frame.height)
        activeView.frame.origin = .zero
        view.frame.size = size
        preferredContentSize = size
        onSizeChange?(size)
    }

    // MARK: - Idle View

    private func buildIdleView() {
        let pad: CGFloat = 16
        let footerH: CGFloat = 24
        let circleSize: CGFloat = 72
        let labelH: CGFloat = 16
        let labelGap: CGFloat = 10
        let sepGap: CGFloat = 12
        let totalH: CGFloat = pad + footerH + sepGap + 1 + sepGap + labelH + labelGap + circleSize + pad

        idleView = NSView(frame: NSRect(x: 0, y: 0, width: W, height: totalH))
        idleView.wantsLayer = true

        var y = pad

        // Footer row: History left, Quit right
        let historyLabel = NSTextField(labelWithString: "History")
        historyLabel.frame = NSRect(x: pad, y: y - 1, width: 50, height: footerH)
        historyLabel.font = .systemFont(ofSize: 12)
        historyLabel.textColor = .secondaryLabelColor

        let historyButton = NSButton(frame: NSRect(x: pad, y: y - 1, width: 50, height: footerH))
        historyButton.title = ""
        historyButton.isTransparent = true
        historyButton.target = self
        historyButton.action = #selector(historyClicked)

        let quitLabel = NSTextField(labelWithString: "Quit")
        quitLabel.frame = NSRect(x: W - pad - 36, y: y - 1, width: 36, height: footerH)
        quitLabel.font = .systemFont(ofSize: 12)
        quitLabel.textColor = .secondaryLabelColor
        quitLabel.alignment = .right

        let quitButton = NSButton(frame: NSRect(x: W - pad - 36, y: y - 1, width: 36, height: footerH))
        quitButton.title = ""
        quitButton.isTransparent = true
        quitButton.target = self
        quitButton.action = #selector(quitClicked)

        y += footerH + sepGap

        let separator = NSBox(frame: NSRect(x: pad, y: y, width: W - pad * 2, height: 1))
        separator.boxType = .separator
        y += 1 + sepGap

        // Subtle hint below button
        let startLabel = NSTextField(labelWithString: "Record")
        startLabel.frame = NSRect(x: 0, y: y, width: W, height: labelH)
        startLabel.font = .systemFont(ofSize: 10)
        startLabel.textColor = .tertiaryLabelColor
        startLabel.alignment = .center
        y += labelH + labelGap

        // Big circular red record button
        let circleX = (W - circleSize) / 2
        let circleButton = NSButton(frame: NSRect(x: circleX, y: y, width: circleSize, height: circleSize))
        circleButton.bezelStyle = .circular
        circleButton.isBordered = false
        circleButton.wantsLayer = true
        circleButton.layer?.cornerRadius = circleSize / 2
        circleButton.layer?.backgroundColor = NSColor(red: 0.88, green: 0.14, blue: 0.14, alpha: 1.0).cgColor

        // Radial gradient overlay for 3D depth
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.frame = CGRect(x: 0, y: 0, width: circleSize, height: circleSize)
        gradient.cornerRadius = circleSize / 2
        gradient.colors = [
            NSColor.white.withAlphaComponent(0.25).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.black.withAlphaComponent(0.15).cgColor
        ]
        gradient.locations = [0.0, 0.45, 1.0]
        gradient.startPoint = CGPoint(x: 0.45, y: 0.65)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        circleButton.layer?.addSublayer(gradient)
        circleButton.target = self
        circleButton.action = #selector(startClicked)
        circleButton.keyEquivalent = "\r"

        // Space bar also triggers start
        let spaceButton = NSButton(frame: .zero)
        spaceButton.isTransparent = true
        spaceButton.target = self
        spaceButton.action = #selector(startClicked)
        spaceButton.keyEquivalent = " "
        idleView.addSubview(spaceButton)

        // Mic icon centered in the circle
        if let micImg = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 26, weight: .medium)) {
            circleButton.image = micImg
            circleButton.imagePosition = .imageOnly
            circleButton.contentTintColor = .white
        }

        // Glow behind the button
        let glowView = NSView(frame: NSRect(x: circleX - 4, y: y - 4, width: circleSize + 8, height: circleSize + 8))
        glowView.wantsLayer = true
        glowView.layer?.cornerRadius = (circleSize + 8) / 2
        glowView.layer?.backgroundColor = NSColor.clear.cgColor
        glowView.layer?.shadowColor = NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0).cgColor
        glowView.layer?.shadowOffset = .zero
        glowView.layer?.shadowRadius = 12
        glowView.layer?.shadowOpacity = 0.4

        idleView.addSubview(glowView)
        idleView.addSubview(circleButton)
        idleView.addSubview(startLabel)
        idleView.addSubview(separator)
        idleView.addSubview(historyLabel)
        idleView.addSubview(historyButton)
        idleView.addSubview(quitLabel)
        idleView.addSubview(quitButton)

        view.addSubview(idleView)
    }

    // MARK: - Recording View

    private func buildRecordingView() {
        let pad: CGFloat = 16
        let btnH: CGFloat = 36
        let btnGap: CGFloat = 8
        let statusH: CGFloat = 20
        let statusGap: CGFloat = 10
        let cancelH: CGFloat = 16
        let hintH: CGFloat = 14
        let hintGap: CGFloat = 4
        let totalH: CGFloat = pad + cancelH + hintGap + hintH + btnGap + btnH + btnGap + btnH + statusGap + statusH + pad

        recordingView = NSView(frame: NSRect(x: 0, y: 0, width: W, height: totalH))
        recordingView.wantsLayer = true

        var y = pad

        // Cancel — plain text link
        let cancelLabel = NSTextField(labelWithString: "Cancel")
        cancelLabel.frame = NSRect(x: 0, y: y, width: W, height: cancelH)
        cancelLabel.font = .systemFont(ofSize: 11)
        cancelLabel.textColor = .tertiaryLabelColor
        cancelLabel.alignment = .center

        let cancelButton = NSButton(frame: NSRect(x: 0, y: y, width: W, height: cancelH))
        cancelButton.title = ""
        cancelButton.isTransparent = true
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.keyEquivalent = "\u{1b}"
        y += cancelH + hintGap

        // Keyboard hints line
        let hintsLabel = NSTextField(labelWithString: "\u{21A9} Stop & Copy     \u{2318}I Improve     Esc Cancel")
        hintsLabel.frame = NSRect(x: 0, y: y, width: W, height: hintH)
        hintsLabel.font = .systemFont(ofSize: 10)
        hintsLabel.textColor = .quaternaryLabelColor
        hintsLabel.alignment = .center
        y += hintH + btnGap

        // Secondary button
        let stopImproveButton = makeButton(
            title: "Stop, Improve & Copy",
            action: #selector(stopImproveClicked),
            isPrimary: false
        )
        stopImproveButton.frame = NSRect(x: pad, y: y, width: W - pad * 2, height: btnH)
        y += btnH + btnGap

        // Primary button
        let stopCopyButton = makeButton(
            title: "Stop & Copy",
            action: #selector(stopCopyClicked),
            isPrimary: true
        )
        stopCopyButton.frame = NSRect(x: pad, y: y, width: W - pad * 2, height: btnH)
        y += btnH + statusGap

        // Status row: red dot + "Recording" left, timer right
        let dotSize: CGFloat = 10
        let glowSize: CGFloat = 24
        let dotCenterX = pad + glowSize / 2
        let dotCenterY = y + statusH / 2

        redDotGlow = NSView(frame: NSRect(
            x: dotCenterX - glowSize / 2,
            y: dotCenterY - glowSize / 2,
            width: glowSize, height: glowSize
        ))
        redDotGlow.wantsLayer = true
        redDotGlow.layer?.backgroundColor = NSColor.clear.cgColor
        redDotGlow.layer?.cornerRadius = glowSize / 2
        redDotGlow.layer?.shadowColor = NSColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1.0).cgColor
        redDotGlow.layer?.shadowOffset = .zero
        redDotGlow.layer?.shadowRadius = 8
        redDotGlow.layer?.shadowOpacity = 0.9

        redDot = NSView(frame: NSRect(
            x: dotCenterX - dotSize / 2, y: dotCenterY - dotSize / 2,
            width: dotSize, height: dotSize
        ))
        redDot.wantsLayer = true
        redDot.layer?.backgroundColor = NSColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1.0).cgColor
        redDot.layer?.cornerRadius = dotSize / 2

        let labelX = pad + glowSize + 6
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
        recordingView.addSubview(hintsLabel)
        recordingView.addSubview(cancelLabel)
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

    private func makeButton(title: String, action: Selector, isPrimary: Bool) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = title
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: isPrimary ? .semibold : .regular)

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
        // Use CABasicAnimation for smooth shadow pulse
        let shadowAnim = CABasicAnimation(keyPath: "shadowOpacity")
        shadowAnim.fromValue = 0.9
        shadowAnim.toValue = 0.0
        shadowAnim.duration = 1.0
        shadowAnim.autoreverses = true
        shadowAnim.repeatCount = .infinity
        shadowAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        redDotGlow?.layer?.add(shadowAnim, forKey: "pulse")

        let dotAnim = CABasicAnimation(keyPath: "opacity")
        dotAnim.fromValue = 1.0
        dotAnim.toValue = 0.4
        dotAnim.duration = 1.0
        dotAnim.autoreverses = true
        dotAnim.repeatCount = .infinity
        dotAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        redDot?.layer?.add(dotAnim, forKey: "pulse")
    }

    private func stopPulse() {
        pulseAnimation?.invalidate()
        pulseAnimation = nil
        redDotGlow?.layer?.removeAnimation(forKey: "pulse")
        redDot?.layer?.removeAnimation(forKey: "pulse")
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

    @objc private func historyClicked() {
        delegate?.popoverDidRequestShowHistory()
    }

    @objc private func quitClicked() {
        delegate?.popoverDidRequestQuit()
    }
}
