import Carbon
import Foundation

/// An enabled keyboard layout and its key code → character translation.
struct Layout {
    /// Key codes that produce characters (ANSI/ISO main block and the keypad).
    static let printableKeys: Set<UInt16> = Set((0...50).map(UInt16.init)).subtracting([36, 48, 51])
        .union([65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92])
    static let spaceKey: UInt16 = 49

    let source: TISInputSource
    let id: String
    private let data: Data

    /// Layouts enabled in System Settings, in menu order. Main thread only.
    static func enabled() -> [Layout] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        return sources.compactMap { source in
            guard let id: String = property(source, kTISPropertyInputSourceID),
                  let data: Data = property(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            return Layout(source: source, id: id, data: data)
        }
    }

    /// Main thread only.
    static func currentID() -> String? {
        property(TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue(), kTISPropertyInputSourceID)
    }

    /// Main thread only.
    func select() {
        TISSelectInputSource(source)
    }

    func string(keyCode: UInt16, shift: Bool, caps: Bool) -> String {
        var modifiers = 0
        if shift { modifiers |= shiftKey }
        if caps { modifiers |= alphaLock }
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw in
            UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress,
                           keyCode, UInt16(kUCKeyActionDown), UInt32(modifiers >> 8) & 0xFF,
                           UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                           &deadKeyState, chars.count, &length, &chars)
        }
        return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
    }

    /// Character → key that types it in this layout.
    func keyMap() -> [Character: (keyCode: UInt16, shift: Bool)] {
        var map: [Character: (keyCode: UInt16, shift: Bool)] = [:]
        for shift in [true, false] {
            for keyCode in Layout.printableKeys.sorted(by: >) {
                let s = string(keyCode: keyCode, shift: shift, caps: false)
                if s.count == 1 { map[s.first!] = (keyCode, shift) }
            }
        }
        return map
    }

    /// Re-types `text` as if its keys had been pressed in the next layout.
    /// The source layout is the one that can type most of the text; ties go to `currentID`.
    static func convert(_ text: String, layouts: [Layout], currentID: String?) -> (text: String, target: Layout)? {
        guard layouts.count > 1 else { return nil }
        let maps = layouts.map { $0.keyMap() }
        let scores = maps.map { map in text.filter { map[$0] != nil }.count }
        let best = scores.max() ?? 0
        guard best > 0 else { return nil }
        let candidates = layouts.indices.filter { scores[$0] == best }
        let from = candidates.first { layouts[$0].id == currentID } ?? candidates[0]
        let target = layouts[(from + 1) % layouts.count]
        let converted = text.map { ch -> String in
            guard let key = maps[from][ch] else { return String(ch) }
            let s = target.string(keyCode: key.keyCode, shift: key.shift, caps: false)
            return s.isEmpty ? String(ch) : s
        }.joined()
        return (converted, target)
    }

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
    }
}
