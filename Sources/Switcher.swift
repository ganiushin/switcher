import AppKit

/// Watches the keyboard and converts the last typed word (or the selection)
/// to the next layout when Option is tapped on its own.
final class Switcher {
    private struct Keystroke {
        let keyCode: UInt16
        let shift: Bool
        let caps: Bool
    }

    private static let optionKeys: Set<Int64> = [58, 61]
    private static let backspaceKey: UInt16 = 51
    private static let maxTapDuration: CFAbsoluteTime = 0.5
    private static let maxBufferLength = 256

    var enabled = true

    /// Keys of the word being typed, plus the spaces after it.
    private var buffer: [Keystroke] = []
    /// The current word can't be tracked reliably (key repeat, deleting into older text); skip it.
    private var poisoned = false
    private var optionDownAt: CFAbsoluteTime?
    private var busy = false
    private var tap: CFMachPort?
    private let worker = DispatchQueue(label: "switcher.worker")

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reset() }
    }

    /// Installs the event tap. Fails until Accessibility access is granted.
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                Unmanaged<Switcher>.fromOpaque(userInfo!).takeUnretainedValue().handle(type, event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            optionDownAt = nil
            reset()
        case .flagsChanged, .keyDown:
            guard event.getIntegerValueField(.eventSourceUserData) != Keys.marker else { return }
            if type == .keyDown { handleKey(event) } else { handleFlags(event) }
        default:
            break
        }
    }

    private func handleFlags(_ event: CGEvent) {
        let isOption = Switcher.optionKeys.contains(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags.intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand, .maskSecondaryFn])
        let now = CFAbsoluteTimeGetCurrent()
        if isOption, modifiers == .maskAlternate {
            optionDownAt = now
        } else if isOption, modifiers.isEmpty, let downAt = optionDownAt {
            optionDownAt = nil
            if now - downAt < Switcher.maxTapDuration { trigger() }
        } else {
            optionDownAt = nil
        }
    }

    private func handleKey(_ event: CGEvent) {
        optionDownAt = nil
        let flags = event.flags
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return reset() }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if keyCode == Switcher.backspaceKey {
            if buffer.isEmpty { poisoned = true } else { buffer.removeLast() }
            return
        }
        guard Layout.printableKeys.contains(keyCode) else { return reset() }
        // Held keys may open the accent popup instead of repeating, so the count is unknown.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            buffer = []
            poisoned = true
            return
        }
        if keyCode == Layout.spaceKey {
            poisoned = false
            if buffer.isEmpty { return }
        } else {
            if poisoned { return }
            if buffer.last?.keyCode == Layout.spaceKey { buffer = [] }
        }
        if buffer.count >= Switcher.maxBufferLength { return reset() }
        buffer.append(Keystroke(keyCode: keyCode, shift: flags.contains(.maskShift), caps: flags.contains(.maskAlphaShift)))
    }

    private func reset() {
        buffer = []
        poisoned = false
    }

    private func trigger() {
        guard enabled, !busy else { return }
        let layouts = Layout.enabled()
        guard layouts.count > 1 else { return }
        let currentID = Layout.currentID()
        busy = true

        if !buffer.isEmpty {
            // The buffer is kept, so a second tap converts the word back.
            let current = layouts.firstIndex { $0.id == currentID } ?? 0
            let target = layouts[(current + 1) % layouts.count]
            let text = buffer.map { target.string(keyCode: $0.keyCode, shift: $0.shift, caps: $0.caps) }.joined()
            let count = buffer.count
            target.select()
            worker.async {
                Keys.backspace(count)
                Keys.type(text)
                DispatchQueue.main.async { self.busy = false }
            }
        } else {
            worker.async {
                var target: Layout?
                if let selected = Selection.read(),
                   let result = Layout.convert(selected, layouts: layouts, currentID: currentID) {
                    Selection.replace(with: result.text)
                    target = result.target
                }
                DispatchQueue.main.async {
                    target?.select()
                    self.busy = false
                }
            }
        }
    }
}
