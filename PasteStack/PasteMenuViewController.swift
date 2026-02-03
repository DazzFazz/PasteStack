import Cocoa

/// Displays the list of clipboard-history items inside the floating
/// `PasteMenuWindow`. Each row shows a number key hint and the item's
/// display label (first 20 characters or content type).
final class PasteMenuViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    /// Called when the user selects an item. The parameter is the item index.
    var onItemSelected: ((Int) -> Void)?

    /// Called when the menu should be dismissed without pasting.
    var onDismiss: (() -> Void)?

    // MARK: - View lifecycle

    override func loadView() {
        let container = NSVisualEffectView()
        container.material = .popover
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        self.view = container

        setupTableView()
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ItemColumn"))
        column.title = ""
        column.isEditable = false
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])
    }

    // MARK: - Data

    func reloadData() {
        tableView.reloadData()
        // Defer selection to avoid layout recursion during window setup
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if ClipboardManager.shared.items.count > 0 {
                self.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }
    }

    // MARK: - Actions

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        onItemSelected?(row)
    }

    /// Selects the item at the given index (triggered by keyboard shortcut).
    func selectItem(at index: Int) {
        guard index >= 0, index < ClipboardManager.shared.items.count else { return }
        onItemSelected?(index)
    }

    // MARK: - Keyboard handling

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onDismiss?()
        case 36, 76: // Return / Enter
            let row = tableView.selectedRow
            if row >= 0 { onItemSelected?(row) }
        case 126: // Up arrow
            let row = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        case 125: // Down arrow
            let maxRow = ClipboardManager.shared.items.count - 1
            let row = min(tableView.selectedRow + 1, maxRow)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        default:
            // Check for number keys 1-9, 0 (maps to items 0-9).
            if let characters = event.charactersIgnoringModifiers, characters.count == 1 {
                let ch = characters.first!
                let index: Int?
                switch ch {
                case "1": index = 0
                case "2": index = 1
                case "3": index = 2
                case "4": index = 3
                case "5": index = 4
                case "6": index = 5
                case "7": index = 6
                case "8": index = 7
                case "9": index = 8
                case "0": index = 9
                default:  index = nil
                }
                if let idx = index {
                    selectItem(at: idx)
                    return
                }
            }
            super.keyDown(with: event)
        }
    }
}

// MARK: - NSTableViewDataSource

extension PasteMenuViewController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return ClipboardManager.shared.items.count
    }
}

// MARK: - NSTableViewDelegate

extension PasteMenuViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ClipboardCell")
        let cell: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        let item = ClipboardManager.shared.items[row]
        let shortcut = row < 9 ? "\(row + 1)" : (row == 9 ? "0" : " ")
        cell.textField?.stringValue = "\(shortcut)  \(item.displayLabel)"

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return PasteMenuRowView()
    }
}

// MARK: - Custom row view for rounded selection highlight

private final class PasteMenuRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let color = NSColor.controlAccentColor.withAlphaComponent(0.25)
            color.setFill()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4)
            path.fill()
        }
    }
}
