import AppKit
import SwiftUI

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class HistoryWindowController {
    private var panel: NSPanel?
    private let store: TranscriptStore

    init(store: TranscriptStore) {
        self.store = store
    }

    func showWindow() {
        if let panel = panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        ensureEditMenu()

        let hostingController = NSHostingController(rootView: HistoryView(store: store))

        let width: CGFloat = 900
        let height: CGFloat = 700

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "MicBar"
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.setContentSize(NSSize(width: width, height: height))
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.midY - height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .visible

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureEditMenu() {
        guard NSApp.mainMenu == nil || NSApp.mainMenu?.item(withTitle: "Edit") == nil else { return }

        let mainMenu = NSApp.mainMenu ?? NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}
