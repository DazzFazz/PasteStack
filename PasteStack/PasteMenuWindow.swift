import Cocoa

/// A borderless, floating panel used to show the clipboard-history picker
/// near the current mouse location or text caret.
final class PasteMenuWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 10),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        // The window should disappear if the user clicks outside it.
        becomesKeyOnlyIfNeeded = true
    }

    // MARK: - Presentation

    /// Shows the window near the current mouse position, sized to fit
    /// the number of clipboard items available.
    func showNearCursor(with viewController: PasteMenuViewController) {
        let items = ClipboardManager.shared.items
        guard !items.isEmpty else { return }

        let rowHeight: CGFloat = 28
        let padding: CGFloat = 8
        let totalHeight = CGFloat(items.count) * rowHeight + padding * 2
        let width: CGFloat = 260

        let mouseLocation = NSEvent.mouseLocation
        let frame = NSRect(
            x: mouseLocation.x,
            y: mouseLocation.y - totalHeight,
            width: width,
            height: totalHeight
        )

        // Set frame BEFORE setting content view controller to avoid layout issues
        setFrame(ensureOnScreen(frame), display: false)

        // Now set the view controller and reload data
        contentViewController = viewController
        viewController.reloadData()

        // Show the window
        orderFrontRegardless()
    }

    /// Ensures the given frame is fully visible on the screen containing
    /// the mouse cursor.
    private func ensureOnScreen(_ desired: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else {
            return desired
        }
        let visible = screen.visibleFrame
        var result = desired

        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }

        return result
    }

    func dismiss() {
        orderOut(nil)
        contentViewController = nil
    }
}
