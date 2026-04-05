import AppKit
import SwiftUI

class TabSelection: ObservableObject {
    @Published var selectedTab: Int = 0
}

class HistoryWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private let store: TranscriptStore
    private let onRecord: () -> Void
    private let onStop: () -> Void
    let tabSelection = TabSelection()

    init(store: TranscriptStore, onRecord: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.store = store
        self.onRecord = onRecord
        self.onStop = onStop
    }

    func showWindow(tab: Int = 0) {
        tabSelection.selectedTab = tab
        if let window = window {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        ensureEditMenu()

        let hostingController = NSHostingController(rootView: HistoryView(store: store, onRecord: onRecord, onStop: onStop, tabSelection: tabSelection))

        let width: CGFloat = 900
        let height: CGFloat = 800

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MicBar"
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.delegate = self
        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Delay slightly so the dock icon doesn't flash
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func ensureEditMenu() {
        guard NSApp.mainMenu == nil || NSApp.mainMenu?.item(withTitle: "Edit") == nil else { return }

        let mainMenu = NSApp.mainMenu ?? NSMenu()

        if mainMenu.item(withTitle: "File") == nil {
            let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let fileMenu = NSMenu(title: "File")
            fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            fileItem.submenu = fileMenu
            mainMenu.addItem(fileItem)
        }

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
