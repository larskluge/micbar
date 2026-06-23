import Cocoa
import ApplicationServices
import CoreGraphics

/// How the transcript ended up in the target app.
enum InjectionResult {
    case inserted    // via Accessibility (true insert at caret)
    case typed       // via synthetic keystrokes
    case pasted      // via clipboard + ⌘V (clipboard restored afterward)
    case copiedOnly  // no Accessibility permission — left on clipboard only

    var notificationTitle: String {
        switch self {
        case .inserted, .typed, .pasted: return "Pasted at cursor"
        case .copiedOnly: return "Copied — enable Accessibility to paste"
        }
    }
}

/// Inserts text where the user's cursor was before MicBar took focus.
///
/// Strategy (best → safest fallback), all gated on Accessibility permission:
///   1. AX `kAXSelectedText` — clean insert at the caret, no clipboard touch.
///   2. Synthetic Unicode typing — no clipboard touch.
///   3. Clipboard + ⌘V — universal last resort; the prior clipboard is restored.
final class TextInjector {
    private let log = Logger.shared

    /// The app that was frontmost before MicBar activated. Capture at record start.
    func captureFrontmostApp() -> NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        log.info("captured frontmost app: \(app?.localizedName ?? "nil")")
        return app
    }

    static func hasAccessibility() -> Bool { AXIsProcessTrusted() }

    /// Triggers the system "grant Accessibility" prompt if not yet trusted.
    @discardableResult
    static func requestAccessibility() -> Bool {
        // Literal key value of kAXTrustedCheckOptionPrompt, used directly to avoid
        // Unmanaged<CFString> import differences across SDKs.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Reactivates `app`, waits for focus to settle, then inserts `text`.
    /// `completion` fires on the main queue with the method that succeeded.
    func inject(_ text: String, into app: NSRunningApplication?, completion: @escaping (InjectionResult) -> Void) {
        app?.activate(options: [.activateIgnoringOtherApps])

        // Give the target app a beat to become frontmost and restore its caret.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            let result = self.perform(text)
            self.log.info("inject result: \(result)")
            completion(result)
        }
    }

    private func perform(_ text: String) -> InjectionResult {
        guard Self.hasAccessibility() else {
            copyToClipboard(text)
            return .copiedOnly
        }
        if axInsert(text) { return .inserted }
        if typeText(text) { return .typed }
        pasteViaClipboard(text)
        return .pasted
    }

    // MARK: - 1. Accessibility insert

    private func axInsert(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return false }
        let el = element as! AXUIElement

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        // Setting selected text replaces the selection, or inserts at the caret
        // when there is no selection.
        return AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    // MARK: - 2. Synthetic typing

    private func typeText(_ text: String) -> Bool {
        guard !text.isEmpty, let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        let units = Array(text.utf16)
        let chunkSize = 20  // keyboardSetUnicodeString is reliable for short runs
        var i = 0
        while i < units.count {
            var buf = Array(units[i..<min(i + chunkSize, units.count)])
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) else { return false }
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
            down.post(tap: .cghidEventTap)
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
                up.post(tap: .cghidEventTap)
            }
            i += chunkSize
        }
        return true
    }

    // MARK: - 3. Clipboard + ⌘V

    private func pasteViaClipboard(_ text: String) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        sendCommandV()
        // Restore the user's clipboard once the paste has had time to read it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.restore(saved, to: pb)
        }
    }

    private func sendCommandV() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey: CGKeyCode = 0x09  // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict = [NSPasteboard.PasteboardType: Data]()
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pb: NSPasteboard) {
        pb.clearContents()
        let items = snapshot.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
}
