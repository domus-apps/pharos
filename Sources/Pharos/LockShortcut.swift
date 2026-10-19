import AppKit
import Carbon.HIToolbox

/* The Locked Awake global shortcut (default ⇧⌘L): spec, persistence, and
   the Carbon hotkey registration — Oriel's shortcut machinery, trimmed to
   Pharos's single action. */

/* One recordable shortcut: a Carbon-compatible key code + modifier mask,
   plus the key's display label captured at record time (deriving labels
   from key codes needs layout-aware translation; capturing is simpler). */
struct ShortcutSpec: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    var displayString: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        /* Derived from the key code where it can be, so a label stored by an
           older build (recorded while Korean input was on: "ㅏ") or under
           another layout still reads right. */
        return symbols + (Self.keyLabel(forKeyCode: keyCode) ?? keyLabel)
    }

    /* For showing the shortcut on an NSMenuItem: the key-equivalent
       character (empty for keys menus can't display) + AppKit flags. */
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        switch Int(keyCode) {
        case kVK_Return: return ("\r", flags)
        case kVK_Space: return (" ", flags)
        default:
            guard keyLabel.count == 1 else { return ("", flags) }
            return (keyLabel.lowercased(), flags)
        }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    static func keyLabel(for event: NSEvent) -> String {
        keyLabel(forKeyCode: UInt32(event.keyCode))
            ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }

    static func keyLabel(forKeyCode keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_ANSI_KeypadEnter: return "⌤"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default:
            if let name = functionKeyNames[Int(keyCode)] { return name }
            return latinCharacters(forKeyCode: UInt16(truncatingIfNeeded: keyCode))?
                .uppercased()
        }
    }

    /* F-keys translate to control characters (F1 is U+0010), which would
       leave the keycap blank. */
    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    /* The key's character on the ASCII-capable layout, so a shortcut
       recorded with Korean (or any non-Latin) input active reads "K", not
       "ㅏ". The user's own Latin layout is used, which keeps Dvorak and
       friends labeled as their users expect. Control characters (Help,
       Clear, …) and AppKit's private-use function-key glyphs aren't
       labels, so those come back nil. */
    private static func latinCharacters(forKeyCode keyCode: UInt16) -> String? {
        /* TIS is main-thread only: HIToolbox aborts the process on
           concurrent calls. Anywhere else the caller's fallback (the
           stored label) stands. */
        guard Thread.isMainThread,
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue()
        else { return nil }
        /* The layout data is borrowed from the source; keep the source
           alive until the translation is done. */
        let translated: String? = withExtendedLifetime(source) {
            guard
                let layoutPointer = TISGetInputSourceProperty(
                    source, kTISPropertyUnicodeKeyLayoutData)
            else { return nil }
            let layoutData =
                Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
            return layoutData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> String? in
                guard
                    let layout = bytes.baseAddress?.assumingMemoryBound(
                        to: UCKeyboardLayout.self)
                else { return nil }
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDown), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState, characters.count, &length, &characters)
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: characters, count: length)
            }
        }
        guard let translated, let scalar = translated.unicodeScalars.first,
            scalar.value >= 0x20, scalar.value != 0x7F,
            !(0xF700...0xF8FF).contains(scalar.value)
        else { return nil }
        return translated
    }
}

/* Persists the user-recorded lock shortcut in UserDefaults and broadcasts
   changes so the app re-registers its hotkey. Same defaults-domain caveat
   as the rest of the app: `swift run` and the bundled app don't share it. */
enum LockShortcutStore {
    static let changed = Notification.Name("Pharos.LockShortcutChanged")
    private static let key = "shortcut.lockScreen"

    static let defaultSpec = ShortcutSpec(
        keyCode: UInt32(kVK_ANSI_L),
        carbonModifiers: UInt32(shiftKey) | UInt32(cmdKey),
        keyLabel: "L")

    static var spec: ShortcutSpec {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                let spec = try? JSONDecoder().decode(ShortcutSpec.self, from: data)
            else { return defaultSpec }
            return spec
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /* Whether the shortcut is live. Registration fails when another app
       already holds the combination exclusively; Settings says so. Posts
       registrationChanged, not changed, which would re-register. */
    static let registrationChanged = Notification.Name("Pharos.LockShortcutRegistrationChanged")
    static var isRegistered = true {
        didSet {
            guard isRegistered != oldValue else { return }
            NotificationCenter.default.post(name: registrationChanged, object: nil)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/* System-wide hotkeys via Carbon's RegisterEventHotKey — ancient but still
   the supported API for global shortcuts, and it works from a plain
   (non-bundled) binary, which keeps `swift run` viable for development. */
final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private static let signature = OSType(0x5048_4C4B)  // 'PHLK'

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        handlers[id] = handler
        hotKeyRefs.append(ref)
        return true
    }

    /* Used both to apply re-recorded shortcuts and to release the hotkey
       while the settings recorder is capturing (a registered hotkey would
       otherwise swallow the very combination being recorded). */
    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }
}
