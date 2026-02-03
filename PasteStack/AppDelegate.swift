import Cocoa
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let pasteMenuWindow = PasteMenuWindow()
    private var pasteMenuVC: PasteMenuViewController?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var clickOutsideMonitor: Any?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        ClipboardManager.shared.startMonitoring()
        registerGlobalHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardManager.shared.stopMonitoring()
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Status bar

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "PasteStack")
                ?? makeTextStatusImage()
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "PasteStack", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let showItem = NSMenuItem(title: "Show Paste Menu", action: #selector(showPasteMenu), keyEquivalent: "V")
        showItem.keyEquivalentModifierMask = [.command, .shift]
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit PasteStack", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Fallback image when SF Symbols are unavailable.
    private func makeTextStatusImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18))
        img.lockFocus()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let str = NSAttributedString(string: "PS", attributes: attributes)
        str.draw(at: NSPoint(x: 1, y: 2))
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    // MARK: - Global hotkey (Cmd + Shift + V)

    private func registerGlobalHotkey() {
        // Global monitor catches the shortcut when another app is focused.
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor catches it when PasteStack itself is focused.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // swallow the event
            }
            return event
        }
    }

    /// Returns `true` if the event was handled (Cmd+Shift+V).
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isShiftCmd = flags == [.command, .shift]

        // 0x09 is the virtual key code for 'V'
        if isShiftCmd && event.keyCode == 0x09 {
            DispatchQueue.main.async { self.togglePasteMenu() }
            return true
        }
        return false
    }

    // MARK: - Paste menu

    @objc private func showPasteMenu() {
        togglePasteMenu()
    }

    private func togglePasteMenu() {
        if pasteMenuWindow.isVisible {
            dismissPasteMenu()
            return
        }

        let items = ClipboardManager.shared.items
        guard !items.isEmpty else { return }

        let vc = PasteMenuViewController()
        vc.onItemSelected = { [weak self] index in
            self?.dismissPasteMenu()
            // Small delay so the floating window is gone before simulating paste.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ClipboardManager.shared.pasteItem(at: index)
            }
        }
        vc.onDismiss = { [weak self] in
            self?.dismissPasteMenu()
        }
        pasteMenuVC = vc

        pasteMenuWindow.showNearCursor(with: vc)

        // Monitor for clicks outside the window to auto-dismiss.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPasteMenu()
        }
    }

    private func dismissPasteMenu() {
        pasteMenuWindow.dismiss()
        pasteMenuVC = nil
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Menu actions

    @objc private func clearHistory() {
        ClipboardManager.shared.clearHistory()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
