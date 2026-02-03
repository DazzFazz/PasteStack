import Cocoa
import Carbon.HIToolbox
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let pasteMenuWindow = PasteMenuWindow()
    private var pasteMenuVC: PasteMenuViewController?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var permissionCheckTimer: Timer?
    private var hasAccessibilityPermission = false

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        ClipboardManager.shared.startMonitoring()
        checkAndSetupAccessibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardManager.shared.stopMonitoring()
        permissionCheckTimer?.invalidate()
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

    // MARK: - Accessibility Permissions

    private func checkAndSetupAccessibility() {
        let hasPermission = AXIsProcessTrusted()

        if hasPermission != hasAccessibilityPermission {
            hasAccessibilityPermission = hasPermission

            if hasPermission {
                print("✅ Accessibility permission granted - enabling keyboard shortcuts")
                registerGlobalHotkey()
                updateStatusBarIcon(enabled: true)
                // Stop checking once we have permission
                permissionCheckTimer?.invalidate()
                permissionCheckTimer = nil
            } else {
                print("⚠️ Accessibility permission not granted - keyboard shortcuts disabled")
                updateStatusBarIcon(enabled: false)
            }
        }

        if !hasAccessibilityPermission {
            // Show alert on first launch
            DispatchQueue.main.async {
                self.showAccessibilityAlert()
            }

            // Start checking periodically for when permissions are granted
            permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkAndSetupAccessibility()
            }
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        PasteStack needs Accessibility permission to:
        • Monitor keyboard shortcuts (Cmd+Shift+V)
        • Simulate paste commands

        Click "Open System Settings" to grant permission, then return to PasteStack.
        No restart is needed - the shortcut will work immediately after granting permission.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Settings to Privacy & Security > Accessibility
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func updateStatusBarIcon(enabled: Bool) {
        guard let button = statusItem.button else { return }

        // Update the icon to show enabled/disabled state
        if enabled {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "PasteStack - Active")
                ?? makeTextStatusImage()
            button.appearsDisabled = false
        } else {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "PasteStack - Needs Permission")
                ?? makeTextStatusImage()
            button.appearsDisabled = true
        }
    }

    // MARK: - Global hotkey (Cmd + Shift + V)

    private func registerGlobalHotkey() {
        // Remove existing monitors if any
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        // Only register if we have accessibility permissions
        guard AXIsProcessTrusted() else {
            print("⚠️ Skipping global hotkey registration - no accessibility permission")
            return
        }

        print("📝 Registering global hotkey (Cmd+Shift+V)")

        // Global monitor catches the shortcut when another app is focused.
        // This requires accessibility permissions.
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
            print("🎯 Cmd+Shift+V detected! Showing paste menu...")
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
            print("📋 Paste menu already visible, dismissing...")
            dismissPasteMenu()
            return
        }

        let items = ClipboardManager.shared.items
        print("📋 Clipboard items count: \(items.count)")
        guard !items.isEmpty else {
            print("⚠️ No clipboard items to show")
            return
        }

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
