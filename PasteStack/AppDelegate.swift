import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let pasteMenuWindow = PasteMenuWindow()
    private var pasteMenuVC: PasteMenuViewController?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var permissionCheckTimer: Timer?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        ClipboardManager.shared.startMonitoring()
        setupHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardManager.shared.stopMonitoring()
        permissionCheckTimer?.invalidate()
        removeEventMonitors()
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

        // No key equivalent here - it conflicts with the global monitor
        let showItem = NSMenuItem(title: "Show Paste Menu  ⌘⇧V", action: #selector(showPasteMenu), keyEquivalent: "")
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

    // MARK: - Hotkey setup

    private func setupHotkey() {
        if AXIsProcessTrusted() {
            registerEventMonitors()
        } else {
            // Show the system permission prompt on a background thread to avoid
            // the "task name port" kernel error that occurs when calling this
            // on the main thread while other processes are in the foreground.
            DispatchQueue.global(qos: .userInitiated).async {
                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                AXIsProcessTrustedWithOptions(opts as CFDictionary)
            }

            // Poll until the user grants permission, then register
            permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    self.registerEventMonitors()
                }
            }
        }
    }

    private func registerEventMonitors() {
        removeEventMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handlePossibleHotkey(event)
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handlePossibleHotkey(event) == true { return nil }
            return event
        }

    }

    private func removeEventMonitors() {
        if let m = globalEventMonitor { NSEvent.removeMonitor(m); globalEventMonitor = nil }
        if let m = localEventMonitor  { NSEvent.removeMonitor(m); localEventMonitor  = nil }
    }

    @discardableResult
    private func handlePossibleHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.command, .shift], event.keyCode == 0x09 else { return false }
        DispatchQueue.main.async { self.togglePasteMenu() }
        return true
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

        guard !ClipboardManager.shared.items.isEmpty else { return }

        let vc = PasteMenuViewController()
        vc.onItemSelected = { [weak self] index in
            self?.dismissPasteMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ClipboardManager.shared.pasteItem(at: index)
            }
        }
        vc.onDismiss = { [weak self] in self?.dismissPasteMenu() }
        pasteMenuVC = vc

        pasteMenuWindow.showNearCursor(with: vc)

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPasteMenu()
        }
    }

    private func dismissPasteMenu() {
        pasteMenuWindow.dismiss()
        pasteMenuVC = nil
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
    }

    // MARK: - Menu actions

    @objc private func clearHistory() {
        ClipboardManager.shared.clearHistory()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
