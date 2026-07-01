import CoreGraphics
import Foundation

/// Legacy preset trigger keys. The live trigger is now a `Set<CGKeyCode>` (see
/// `AppshotsModel.triggerKey`); this enum is kept only to migrate the old
/// persisted value and to express the default/preset key-code sets.
public enum AppshotsHotKey: String, Sendable {
    case command
    case option
    case shift
    case none

    public static let defaultValue: AppshotsHotKey = .option

    /// Both-sides modifier key codes for this preset (e.g. left + right Option).
    public var triggerKeyCodes: Set<CGKeyCode> {
        switch self {
        case .command: [.kVK_Command, .kVK_RightCommand]
        case .option: [.kVK_Option, .kVK_RightOption]
        case .shift: [.kVK_Shift, .kVK_RightShift]
        case .none: []
        }
    }

    public static func decode(from rawValue: String?) -> AppshotsHotKey {
        guard let rawValue else {
            return .defaultValue
        }

        if let hotKey = AppshotsHotKey(rawValue: rawValue) {
            return hotKey
        }

        return decodeLegacyJSON(from: rawValue) ?? .defaultValue
    }

    private static func decodeLegacyJSON(from rawValue: String) -> AppshotsHotKey? {
        guard let data = rawValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let modifierPair = object["modifierPair"] as? String {
            return AppshotsHotKey(rawValue: modifierPair)
        }

        if let modifierKeys = object["modifierKeys"] as? [String] {
            let keySet = Set(modifierKeys)
            if keySet == ["leftCommand", "rightCommand"] { return .command }
            if keySet == ["leftOption", "rightOption"] { return .option }
            if keySet == ["leftShift", "rightShift"] { return .shift }
        }

        return nil
    }
}
