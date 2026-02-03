import Cocoa

/// Monitors the system clipboard and maintains a stack of up to 10 recent items.
final class ClipboardManager {

    static let shared = ClipboardManager()

    /// Maximum number of items to keep in the stack.
    static let maxItems = 10

    /// The clipboard history stack. Index 0 is the most recent item.
    private(set) var items: [ClipboardItem] = []

    /// The last observed change count on the general pasteboard.
    private var lastChangeCount: Int = 0

    /// Timer that polls the pasteboard for changes.
    private var pollTimer: Timer?

    /// When true, the next pasteboard change is one we caused (pasting back)
    /// and should be ignored so it doesn't re-enter the history.
    private var ignoreNextChange = false

    private init() {}

    // MARK: - Lifecycle

    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Polling

    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        guard let item = ClipboardItem(from: pasteboard) else { return }
        pushItem(item)
    }

    // MARK: - Stack management

    private func pushItem(_ item: ClipboardItem) {
        // Avoid storing consecutive duplicates (same plain text).
        if let existing = items.first, existing.plainText != nil, existing.plainText == item.plainText {
            return
        }
        items.insert(item, at: 0)
        if items.count > ClipboardManager.maxItems {
            items.removeLast()
        }
    }

    // MARK: - Pasting a selected item

    /// Writes the item at `index` onto the system pasteboard and simulates
    /// a Cmd+V keystroke so the frontmost application receives it.
    func pasteItem(at index: Int) {
        guard index >= 0, index < items.count else { return }
        let item = items[index]

        ignoreNextChange = true
        item.writeToPasteboard(NSPasteboard.general)

        // Brief delay to let the pasteboard settle before simulating keystrokes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()
        }
    }

    /// Removes all items from the history.
    func clearHistory() {
        items.removeAll()
    }

    // MARK: - Simulate Cmd+V

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)   // 0x09 = 'V'
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
