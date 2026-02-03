import Cocoa

/// Represents a single item captured from the system clipboard.
final class ClipboardItem {

    /// The pasteboard types this item contains, in priority order.
    let types: [NSPasteboard.PasteboardType]

    /// Raw data keyed by pasteboard type.
    private let dataByType: [NSPasteboard.PasteboardType: Data]

    /// Plain-text representation (if any).
    let plainText: String?

    /// Timestamp when the item was captured.
    let capturedAt: Date

    // MARK: - Initialisation

    /// Snapshots whatever is currently on the given pasteboard.
    init?(from pasteboard: NSPasteboard) {
        guard let items = pasteboard.pasteboardItems, let first = items.first else {
            return nil
        }

        let itemTypes = first.types
        guard !itemTypes.isEmpty else { return nil }

        var data = [NSPasteboard.PasteboardType: Data]()
        for type in itemTypes {
            if let d = first.data(forType: type) {
                data[type] = d
            }
        }
        guard !data.isEmpty else { return nil }

        self.types = itemTypes
        self.dataByType = data
        self.plainText = first.string(forType: .string)
        self.capturedAt = Date()
    }

    // MARK: - Writing back to pasteboard

    /// Writes this item back onto the given pasteboard, replacing its contents.
    func writeToPasteboard(_ pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in dataByType {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }

    // MARK: - Display helpers

    /// A short label suitable for showing in the paste menu.
    /// Shows the first 20 characters of text content, or the broad content
    /// kind (e.g. "Image", "File", "PDF") for non-text items.
    var displayLabel: String {
        if let text = plainText {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "[Empty text]" }
            if trimmed.count <= 20 { return trimmed }
            return String(trimmed.prefix(20)) + "..."
        }

        // Determine a user-friendly kind from the pasteboard types.
        if types.contains(where: { $0.rawValue.contains("image") || $0 == .png || $0 == .tiff }) {
            return "[Image]"
        }
        if types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("public.file-url")) {
            if let data = dataByType[.fileURL] ?? dataByType[NSPasteboard.PasteboardType("public.file-url")],
               let urlString = String(data: data, encoding: .utf8),
               let url = URL(string: urlString) {
                let name = url.lastPathComponent
                if name.count <= 20 { return "[File: \(name)]" }
                return "[File: \(String(name.prefix(17)))...]"
            }
            return "[File]"
        }
        if types.contains(.pdf) || types.contains(NSPasteboard.PasteboardType("com.adobe.pdf")) {
            return "[PDF]"
        }
        if types.contains(.rtf) || types.contains(NSPasteboard.PasteboardType("public.rtf")) {
            return "[Rich Text]"
        }
        if types.contains(.html) || types.contains(NSPasteboard.PasteboardType("public.html")) {
            return "[HTML]"
        }

        return "[Clipboard Data]"
    }
}
