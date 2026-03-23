import AppKit

protocol AnswerPopoverDelegate: AnyObject {
    func answerPopoverDidRequestClose()
}

class AnswerPopoverController: NSViewController {
    weak var delegate: AnswerPopoverDelegate?

    private var spinnerView: NSView!
    private var answerView: NSView!
    private var answerTextView: NSTextView!
    private var answerScrollView: NSScrollView!
    private var answerErrorLabel: NSTextField!
    private var rawAnswerText: String = ""

    private let maxW: CGFloat = 500
    private let minW: CGFloat = 280

    var onSizeChange: ((NSSize) -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: minW, height: 90))
        view.wantsLayer = true

        buildSpinnerView()
        buildAnswerView()

        showSpinner()
    }

    func showSpinner() {
        _ = self.view
        spinnerView.isHidden = false
        answerView.isHidden = true
        setViewSize(spinnerView, width: minW)
    }

    func showAnswer(text: String, error: String?) {
        _ = self.view
        spinnerView.isHidden = true
        answerView.isHidden = false
        rawAnswerText = text
        layoutAnswerView(text: text, error: error)
    }

    // MARK: - Spinner View

    private func buildSpinnerView() {
        let h: CGFloat = 90
        spinnerView = NSView(frame: NSRect(x: 0, y: 0, width: minW, height: h))
        spinnerView.wantsLayer = true

        // Wrapper centered in spinnerView via autoresizing
        let contentH: CGFloat = 20 + 8 + 20
        let wrapper = NSView(frame: NSRect(x: (minW - 120) / 2, y: (h - contentH) / 2, width: 120, height: contentH))
        wrapper.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]

        let spinner = NSProgressIndicator(frame: NSRect(x: (120 - 20) / 2, y: 28, width: 20, height: 20))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "Answering...")
        label.frame = NSRect(x: 0, y: 0, width: 120, height: 20)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        wrapper.addSubview(spinner)
        wrapper.addSubview(label)
        spinnerView.addSubview(wrapper)
        view.addSubview(spinnerView)
    }

    // MARK: - Answer View

    private func buildAnswerView() {
        let pad: CGFloat = 16
        answerView = NSView(frame: NSRect(x: 0, y: 0, width: maxW, height: 120))
        answerView.wantsLayer = true

        let headerLabel = NSTextField(labelWithString: "Answer")
        headerLabel.frame = NSRect(x: pad, y: 0, width: 60, height: 16)
        headerLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.tag = 100

        answerScrollView = NSScrollView(frame: NSRect(x: pad, y: 0, width: maxW - pad * 2, height: 60))
        answerScrollView.hasVerticalScroller = true
        answerScrollView.hasHorizontalScroller = false
        answerScrollView.autohidesScrollers = true
        answerScrollView.borderType = .noBorder
        answerScrollView.drawsBackground = false

        answerTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: answerScrollView.contentSize.width, height: 60))
        answerTextView.isEditable = false
        answerTextView.isSelectable = true
        answerTextView.isRichText = true
        answerTextView.font = .systemFont(ofSize: 13)
        answerTextView.textColor = .labelColor
        answerTextView.backgroundColor = .clear
        answerTextView.textContainerInset = NSSize(width: 0, height: 4)
        answerTextView.textContainer?.lineFragmentPadding = 0
        answerTextView.isVerticallyResizable = true
        answerTextView.isHorizontallyResizable = false
        answerTextView.textContainer?.widthTracksTextView = true
        answerTextView.autoresizingMask = [.width]

        answerScrollView.documentView = answerTextView

        answerErrorLabel = NSTextField(labelWithString: "")
        answerErrorLabel.frame = NSRect(x: pad, y: 0, width: maxW - pad * 2, height: 16)
        answerErrorLabel.font = .systemFont(ofSize: 11)
        answerErrorLabel.textColor = .systemRed
        answerErrorLabel.lineBreakMode = .byWordWrapping
        answerErrorLabel.maximumNumberOfLines = 3
        answerErrorLabel.isHidden = true

        // Copy & Close button (primary)
        let copyButton = NSButton(frame: .zero)
        copyButton.title = "Copy & Close"
        copyButton.target = self
        copyButton.action = #selector(copyCloseClicked)
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .large
        copyButton.font = .systemFont(ofSize: 13, weight: .semibold)
        copyButton.keyEquivalent = "\r"
        copyButton.contentTintColor = .white
        copyButton.bezelColor = .controlAccentColor
        copyButton.tag = 101

        // Close button (secondary)
        let closeButton = NSButton(frame: .zero)
        closeButton.title = "Close"
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .large
        closeButton.font = .systemFont(ofSize: 13)
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.tag = 102

        answerView.addSubview(headerLabel)
        answerView.addSubview(answerScrollView)
        answerView.addSubview(answerErrorLabel)
        answerView.addSubview(copyButton)
        answerView.addSubview(closeButton)
        view.addSubview(answerView)
    }

    // MARK: - Markdown rendering

    private func renderMarkdown(_ text: String) -> NSAttributedString {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bodyColor = NSColor.labelColor
        let codeBackground = isDark
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(white: 0.0, alpha: 0.05)
        let bodyFont = NSFont.systemFont(ofSize: 13)

        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else {
            return NSAttributedString(string: text, attributes: [
                .font: bodyFont, .foregroundColor: bodyColor,
            ])
        }

        // Phase 1: Process inline intents (bold, italic, code)
        for (intentValue, range) in attributed.runs[\.inlinePresentationIntent] {
            guard let intent = intentValue else { continue }
            var container = AttributeContainer()
            if intent.contains(.code) {
                container.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                container.backgroundColor = codeBackground
            } else {
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                if !traits.isEmpty {
                    let descriptor = bodyFont.fontDescriptor.withSymbolicTraits(traits)
                    container.font = NSFont(descriptor: descriptor, size: bodyFont.pointSize) ?? bodyFont
                }
            }
            attributed[range].mergeAttributes(container)
        }

        // Phase 2: Process block intents in reverse — insert newlines and apply block styling
        let blockRuns = attributed.runs[\.presentationIntent].map { ($0.0, $0.1) }
        for (intentValue, range) in blockRuns.reversed() {
            guard let intent = intentValue else { continue }

            var blockFont: NSFont = bodyFont
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.paragraphSpacing = 6
            var prefix = ""

            for component in intent.components {
                switch component.kind {
                case .header(level: let level):
                    switch level {
                    case 1: blockFont = .systemFont(ofSize: 20, weight: .bold)
                    case 2: blockFont = .systemFont(ofSize: 17, weight: .bold)
                    case 3: blockFont = .systemFont(ofSize: 15, weight: .semibold)
                    default: blockFont = .systemFont(ofSize: 14, weight: .semibold)
                    }
                    paraStyle.paragraphSpacing = 8

                case .listItem(ordinal: let ordinal):
                    // Check if parent is ordered or unordered
                    let isOrdered = intent.components.contains { comp in
                        if case .orderedList = comp.kind { return true }
                        return false
                    }
                    prefix = isOrdered ? "  \(ordinal).  " : "  \u{2022}  "
                    paraStyle.paragraphSpacing = 2
                    paraStyle.headIndent = 24
                    let tab = NSTextTab(textAlignment: .left, location: 24)
                    paraStyle.tabStops = [tab]

                case .codeBlock:
                    blockFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
                    paraStyle.paragraphSpacing = 4

                case .thematicBreak:
                    var rule = AttributedString("───────────────────")
                    rule.font = NSFont.systemFont(ofSize: 8)
                    rule.foregroundColor = NSColor.separatorColor
                    attributed.replaceSubrange(range, with: rule)

                default:
                    break
                }
            }

            // Apply block font (only override if not already set by inline processing)
            for (inlineIntent, subRange) in attributed[range].runs[\.inlinePresentationIntent] {
                if inlineIntent == nil || !inlineIntent!.contains(.code) {
                    // Only set font if no inline code
                    if attributed[subRange].font == nil || (blockFont != bodyFont) {
                        attributed[subRange].font = blockFont
                    }
                }
            }

            // Apply paragraph style and base color
            var container = AttributeContainer()
            container.paragraphStyle = paraStyle
            container.foregroundColor = bodyColor
            if intent.components.contains(where: { if case .codeBlock = $0.kind { return true }; return false }) {
                container.backgroundColor = codeBackground
            }
            attributed[range].mergeAttributes(container)

            // Insert list prefix
            if !prefix.isEmpty {
                var prefixAttr = AttributedString(prefix)
                prefixAttr.font = bodyFont
                prefixAttr.foregroundColor = NSColor.secondaryLabelColor
                prefixAttr.paragraphStyle = paraStyle
                attributed.insert(prefixAttr, at: range.lowerBound)
            }

            // Insert newline before block (except the first one)
            if range.lowerBound != attributed.startIndex {
                attributed.characters.insert(contentsOf: "\n", at: range.lowerBound)
            }
        }

        // Convert to NSAttributedString, apply base font where missing
        let nsAttr = NSMutableAttributedString(attributed)
        let fullRange = NSRange(location: 0, length: nsAttr.length)
        nsAttr.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil {
                nsAttr.addAttribute(.font, value: bodyFont, range: range)
            }
        }
        nsAttr.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil {
                nsAttr.addAttribute(.foregroundColor, value: bodyColor, range: range)
            }
        }

        // Trim trailing newlines
        while nsAttr.length > 0 && nsAttr.string.hasSuffix("\n") {
            nsAttr.deleteCharacters(in: NSRange(location: nsAttr.length - 1, length: 1))
        }

        return nsAttr
    }

    // MARK: - Layout

    private func layoutAnswerView(text: String, error: String?) {
        let pad: CGFloat = 16
        let btnH: CGFloat = 36
        let btnGap: CGFloat = 8
        let headerH: CGFloat = 16
        let headerGap: CGFloat = 4
        let textGap: CGFloat = 8

        // Get available screen height for the popover
        let screenH = NSScreen.main?.visibleFrame.height ?? 800
        let maxTextH = screenH - 160 // leave room for header, buttons, padding, popover chrome

        let hasError = error != nil && text.isEmpty
        let measureW = maxW - pad * 2

        if hasError {
            answerTextView.string = ""
        } else {
            let attributed = renderMarkdown(text)
            answerTextView.textStorage?.setAttributedString(attributed)
        }
        answerErrorLabel.stringValue = error ?? ""
        answerErrorLabel.isHidden = !hasError

        // Measure rendered text height at target width
        let textH: CGFloat
        let needsScroll: Bool
        if hasError {
            textH = 0
            needsScroll = false
        } else {
            // Set container width before measuring
            answerTextView.textContainer?.containerSize = NSSize(width: measureW, height: .greatestFiniteMagnitude)
            answerTextView.layoutManager?.ensureLayout(for: answerTextView.textContainer!)
            let usedRect = answerTextView.layoutManager!.usedRect(for: answerTextView.textContainer!)
            let naturalTextH = ceil(usedRect.height) + 8
            needsScroll = naturalTextH > maxTextH
            textH = needsScroll ? maxTextH : naturalTextH
        }
        answerScrollView.hasVerticalScroller = needsScroll
        // When content fits, prevent any scrolling by constraining the text container
        answerTextView.isVerticallyResizable = needsScroll
        if !needsScroll {
            answerTextView.textContainer?.containerSize = NSSize(width: measureW, height: textH)
        }

        let errorH: CGFloat = hasError ? 32 : 0

        var y = pad

        // Buttons side by side at bottom
        let halfW = (measureW - btnGap) / 2
        if let closeButton = answerView.viewWithTag(102) as? NSButton {
            closeButton.frame = NSRect(x: pad, y: y, width: halfW, height: btnH)
        }
        if let copyButton = answerView.viewWithTag(101) as? NSButton {
            copyButton.frame = NSRect(x: pad + halfW + btnGap, y: y, width: halfW, height: btnH)
        }
        y += btnH + textGap

        // Error label
        if hasError {
            answerErrorLabel.frame = NSRect(x: pad, y: y, width: measureW, height: errorH)
            y += errorH + textGap
        }

        // Text scroll view
        if !hasError {
            answerScrollView.frame = NSRect(x: pad, y: y, width: measureW, height: textH)
            answerTextView.frame = NSRect(x: 0, y: 0, width: measureW, height: textH)
            y += textH + headerGap
        }

        // Header
        if let headerLabel = answerView.viewWithTag(100) {
            headerLabel.frame = NSRect(x: pad, y: y, width: 60, height: headerH)
        }
        y += headerH + pad

        answerView.frame = NSRect(x: 0, y: 0, width: maxW, height: y)
        setViewSize(answerView, width: maxW)
    }

    private func setViewSize(_ activeView: NSView, width: CGFloat) {
        let size = NSSize(width: width, height: activeView.frame.height)
        activeView.frame.origin = .zero
        view.frame.size = size
        preferredContentSize = size
        onSizeChange?(size)
    }

    // MARK: - Actions

    @objc private func copyCloseClicked() {
        if !rawAnswerText.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rawAnswerText, forType: .string)
        }
        delegate?.answerPopoverDidRequestClose()
    }

    @objc private func closeClicked() {
        delegate?.answerPopoverDidRequestClose()
    }
}
