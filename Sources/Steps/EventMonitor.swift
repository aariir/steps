import AppKit
import CoreGraphics
import QuartzCore
import StepsCore

enum MonitorEvent {
    case click(ClickKind, CGPoint, TimeInterval)
    case typed(String)
    case shortcut(String)
    case key(String)
    case scroll(down: Bool)
}

/// Global listen-only event tap (needs Input Monitoring permission).
final class EventMonitor {
    var onEvent: ((MonitorEvent) -> Void)?
    var onToggleHotkey: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var typed = ""
    private var typedTimer: Timer?
    private var scrolling = false
    private var scrollTimer: Timer?

    private static let special: [Int: String] = [36: "Return", 76: "Enter", 48: "Tab", 53: "Escape",
                                                  123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow"]

    func start() -> Bool {
        guard let tap = Self.makeTap(callback: { _, type, event, refcon in
            let me = Unmanaged<EventMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            me.handle(type, event)
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private static func makeTap(callback: @escaping CGEventTapCallBack, userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
        return CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                 eventsOfInterest: mask, callback: callback, userInfo: userInfo)
    }

    /// True if a listen-only tap can actually be created right now (the real test for click-recording access).
    static func canCreateTap() -> Bool {
        guard let tap = makeTap(callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    func stop() {
        flushTyped()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        typedTimer?.invalidate(); scrollTimer?.invalidate()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown, .rightMouseDown:
            flushTyped()
            let state = event.getIntegerValueField(.mouseEventClickState)
            // Repeat clicks of a double-click are reported as plain clicks so the builder drops them.
            let kind: ClickKind = type == .rightMouseDown ? .right : .left
            onEvent?(.click(kind, event.location, CACurrentMediaTime()))
            _ = state
        case .scrollWheel:
            guard !scrolling else { armScrollTimer(); return }
            scrolling = true
            flushTyped()
            onEvent?(.scroll(down: event.getDoubleValueField(.scrollWheelEventDeltaAxis1) < 0))
            armScrollTimer()
        case .keyDown:
            handleKey(event)
        default: break
        }
    }

    private func armScrollTimer() {
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.scrolling = false
        }
    }

    private func handleKey(_ event: CGEvent) {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if code == 15 && flags.contains(.maskCommand) && flags.contains(.maskAlternate) {
            onToggleHotkey?()
            return
        }

        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        let text = String(utf16CodeUnits: chars, count: length)

        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            flushTyped()
            var prefix = ""
            if flags.contains(.maskControl) { prefix += "⌃" }
            if flags.contains(.maskAlternate) { prefix += "⌥" }
            if flags.contains(.maskShift) { prefix += "⇧" }
            if flags.contains(.maskCommand) { prefix += "⌘" }
            let key = Self.special[code] ?? (text.isEmpty ? "key \(code)" : text.uppercased())
            onEvent?(.shortcut(prefix + key))
            return
        }

        if code == 51 { // Delete edits the typed buffer instead of becoming a step
            if !typed.isEmpty { typed.removeLast(); armTypedTimer() }
            return
        }
        if let name = Self.special[code] {
            flushTyped()
            onEvent?(.key(name))
            return
        }
        let printable = text.filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 } }
        guard !printable.isEmpty else { return }
        typed += printable
        armTypedTimer()
    }

    private func armTypedTimer() {
        typedTimer?.invalidate()
        typedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.flushTyped()
        }
    }

    private func flushTyped() {
        typedTimer?.invalidate()
        guard !typed.isEmpty else { return }
        let t = typed
        typed = ""
        onEvent?(.typed(t))
    }
}
