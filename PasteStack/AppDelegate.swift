import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// Virtual key code for 'V'
private let kVK_ANSI_V: UInt32 = 0x09

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let pasteMenuWindow = PasteMenuWindow()
    private var pasteMenuVC: PasteMenuViewController?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var permissionCheckTimer: Timer?
    private var hasAccessibilityPermission = false
    private var hotKeyRef: EventHotKeyRef?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        ClipboardManager.shared.startMonitoring()
        checkAndSetupAccessibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardManager.shared.stopMonitoring()
        permissionCheckTimer?.invalidate()
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
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

        // Always register the hotkey first (it works without accessibility permission)
        if hotKeyRef == nil {
            registerGlobalHotkey()
        }

        if hasPermission != hasAccessibilityPermission {
            hasAccessibilityPermission = hasPermission

            if hasPermission {
                print("✅ Accessibility permission granted - paste simulation enabled")
                updateStatusBarIcon(enabled: true)
                // Stop checking once we have permission
                permissionCheckTimer?.invalidate()
                permissionCheckTimer = nil
            } else {
                print("⚠️ Accessibility permission not granted - paste simulation disabled")
                updateStatusBarIcon(enabled: false)

                // Start checking periodically for when permissions are granted (don't show alert, it's annoying)
                if permissionCheckTimer == nil {
                    permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                        self?.checkAndSetupAccessibility()
                    }
                }
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
        // Unregister existing hotkey if any
        if let hotKey = hotKeyRef {
            print("🔄 Unregistering existing hotkey")
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }

        print("📝 Attempting to register global hotkey (Cmd+Shift+V) using Carbon Event Manager")
        print("   Key code: 0x09 (V), Modifiers: Cmd+Shift")

        // Use Carbon Event Manager for global hotkey - this is more reliable
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // Install event handler
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            print("🔔 Event handler called!")

            guard let userData = userData else {
                print("❌ No userData in event handler")
                return OSStatus(eventNotHandledErr)
            }

            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            if err != noErr {
                print("❌ Failed to get event parameter: \(err)")
                return OSStatus(eventNotHandledErr)
            }

            print("✅ Got hotkey event with ID: \(hotKeyID.id)")

            guard hotKeyID.id == 1 else {
                print("⚠️ Hotkey ID mismatch, expected 1 got \(hotKeyID.id)")
                return OSStatus(eventNotHandledErr)
            }

            // Call the handler
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                print("🎯 Cmd+Shift+V detected via Carbon! Showing paste menu...")
                appDelegate.togglePasteMenu()
            }

            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        print("   Event handler installation status: \(handlerStatus)")

        // Register Cmd+Shift+V hotkey
        var hotKeyID = EventHotKeyID(signature: OSType(0x50535456), id: 1) // 'PSTV'
        let modifiers = UInt32(cmdKey | shiftKey)

        print("   Registering with signature: 0x50535456, id: 1")

        var hotKeyRefTemp: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), modifiers, hotKeyID,
                                        GetApplicationEventTarget(), 0, &hotKeyRefTemp)

        if status == noErr {
            hotKeyRef = hotKeyRefTemp
            print("✅ Global hotkey registered successfully!")
            print("   HotKey reference: \(String(describing: hotKeyRef))")
        } else {
            print("❌ Failed to register global hotkey with status: \(status)")
            print("   This might mean:")
            print("   - Another app is using this shortcut")
            print("   - System shortcut conflict")
            print("   - Missing permissions")
        }
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
