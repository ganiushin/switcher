import AppKit
import ApplicationServices

/// Synthetic keyboard output. Safe to call off the main thread.
enum Keys {
    /// Tag on our own events so the event tap ignores them.
    static let marker: Int64 = 0x5357_4348

    private static let source = CGEventSource(stateID: .privateState)

    static func tap(_ keyCode: CGKeyCode, flags: CGEventFlags = [], text: String? = nil) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags = flags
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
            usleep(1000)
        }
    }

    static func backspace(_ count: Int) {
        for _ in 0..<count { tap(51) }
    }

    static func type(_ text: String) {
        for ch in text { tap(0, text: String(ch)) }
    }
}

/// Reading and replacing the selected text of the frontmost app. Call off the main thread.
enum Selection {
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Selected text, or nil when there is none. Asks Accessibility first and
    /// falls back to Cmd+C for apps that don't expose their selection.
    static func read() -> String? {
        if let text = readViaAccessibility() { return text.isEmpty ? nil : text }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let count = pasteboard.changeCount
        Keys.tap(8, flags: .maskCommand) // Cmd+C
        var text: String?
        for _ in 0..<30 {
            usleep(10_000)
            if pasteboard.changeCount != count {
                text = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != count { restore(pasteboard, saved) }
        return text?.isEmpty == false ? text : nil
    }

    /// Pastes `text` over the selection, then puts the clipboard back.
    static func replace(with text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transientType)
        Keys.tap(9, flags: .maskCommand) // Cmd+V
        usleep(300_000)
        restore(pasteboard, saved)
    }

    private static func readViaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ pasteboard: NSPasteboard, _ saved: [[(NSPasteboard.PasteboardType, Data)]]) {
        pasteboard.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
