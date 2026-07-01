import Carbon
import CoreGraphics
import SwiftUI

// Ported from Loop (github.com/MrKai77/Loop) — Loop/Extensions/CGKeyCode+Extensions.swift.
// Trimmed to the modifier-key subset Appshots' trigger recorder needs.

extension CGKeyCode {
    // Raw codes from HIToolbox's Events.h.
    public static let kVK_Escape: CGKeyCode = 0x35
    public static let kVK_Command: CGKeyCode = 0x37
    static let kVK_Shift: CGKeyCode = 0x38
    public static let kVK_Option: CGKeyCode = 0x3A
    static let kVK_Control: CGKeyCode = 0x3B
    public static let kVK_RightCommand: CGKeyCode = 0x36
    static let kVK_RightShift: CGKeyCode = 0x3C
    public static let kVK_RightOption: CGKeyCode = 0x3D
    static let kVK_RightControl: CGKeyCode = 0x3E
    static let kVK_Function: CGKeyCode = 0x3F

    var baseModifier: CGKeyCode {
        switch self {
        case .kVK_RightShift: .kVK_Shift
        case .kVK_RightCommand: .kVK_Command
        case .kVK_RightOption: .kVK_Option
        case .kVK_RightControl: .kVK_Control
        default: self
        }
    }

    var isModifier: Bool {
        (.kVK_RightCommand ... .kVK_Function).contains(self)
    }

    public var isModifierOnRightSide: Bool {
        let rightModifiers: Set<CGKeyCode> = [.kVK_RightCommand, .kVK_RightControl, .kVK_RightOption, .kVK_RightShift]
        return rightModifiers.contains(self)
    }

    /// Make sure to use baseModifier before using this!
    private static let modifierToSystemImage: [CGKeyCode: String] = [
        .kVK_Function: "globe",
        .kVK_Shift: "shift",
        .kVK_Command: "command",
        .kVK_Control: "control",
        .kVK_Option: "option"
    ]

    public var modifierSystemImage: String? {
        CGKeyCode.modifierToSystemImage[baseModifier]
    }
}

extension CGKeyCode {
    // Common non-modifier keys we want to migrate/print by raw code.
    static let kVK_Return: CGKeyCode = 0x24
    static let kVK_Tab: CGKeyCode = 0x30
    static let kVK_Space: CGKeyCode = 0x31
    static let kVK_Delete: CGKeyCode = 0x33
    static let kVK_ForwardDelete: CGKeyCode = 0x75
    static let kVK_Home: CGKeyCode = 0x73
    static let kVK_End: CGKeyCode = 0x77
    static let kVK_PageUp: CGKeyCode = 0x74
    static let kVK_PageDown: CGKeyCode = 0x79
    static let kVK_LeftArrow: CGKeyCode = 0x7B
    static let kVK_RightArrow: CGKeyCode = 0x7C
    static let kVK_DownArrow: CGKeyCode = 0x7D
    static let kVK_UpArrow: CGKeyCode = 0x7E
    static let kVK_ANSI_KeypadEnter: CGKeyCode = 0x4C

    /// The four modifiers that make up the "Hyper" key (⌃⌥⇧⌘), side-independent.
    static let hyperModifiers: Set<CGKeyCode> = [.kVK_Control, .kVK_Option, .kVK_Shift, .kVK_Command]

    /// Glyphs for keys with no printable character (mirrors Loop's `keyToString`,
    /// trimmed to the keys a trigger realistically uses).
    private static let specialKeyStrings: [CGKeyCode: String] = [
        .kVK_Return: "↩", .kVK_ANSI_KeypadEnter: "↩",
        .kVK_Tab: "⇥", .kVK_Space: "␣",
        .kVK_Delete: "⌫", .kVK_ForwardDelete: "⌦",
        .kVK_Escape: "⎋",
        .kVK_Home: "↖", .kVK_End: "↘",
        .kVK_PageUp: "⇞", .kVK_PageDown: "⇟",
        .kVK_UpArrow: "↑", .kVK_DownArrow: "↓",
        .kVK_LeftArrow: "←", .kVK_RightArrow: "→",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
        0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
        0x67: "F11", 0x6F: "F12"
    ]

    /// A user-facing label for a non-modifier key, e.g. "S", "↩", "→".
    /// Uses the current keyboard layout for printable keys.
    public var humanReadable: String? {
        if let special = CGKeyCode.specialKeyStrings[self] {
            return special
        }
        return CGKeyCode.translatedCharacter(for: self)
    }

    private static func translatedCharacter(for keyCode: CGKeyCode) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutPointer, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let error = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0, // no modifiers
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )

        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

extension Set<CGKeyCode> {
    /// Maps all modifier keys to their base (side-independent) variant.
    var baseModifiers: Set<CGKeyCode> {
        Set(map(\.baseModifier))
    }

    /// The modifier keys in this set.
    public var modifiers: Set<CGKeyCode> { filter(\.isModifier) }

    /// The non-modifier keys in this set.
    public var regularKeys: Set<CGKeyCode> { filter { !$0.isModifier } }

    /// True when the modifier portion is exactly the Hyper chord (⌃⌥⇧⌘).
    public var isHyper: Bool { modifiers.baseModifiers == CGKeyCode.hyperModifiers }
}
