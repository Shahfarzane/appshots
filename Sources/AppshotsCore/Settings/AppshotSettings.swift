import Foundation

/// How Appshots should behave when launched at login / from the CLI.
///
/// Encoded as lowercase strings (`"none"`, `"gui"`, `"headless"`) for a stable,
/// human-editable `config.json`. Consumed by a later phase; defined here so the
/// settings schema is complete.
public enum StartupMode: String, Codable, Sendable, CaseIterable {
    case none
    case gui
    case headless
}

/// The canonical, file-backed settings shared by the GUI app and the
/// `appshotsctl` CLI. Persisted as `~/.appshots/config.json` via
/// ``AppshotSettingsStore``.
///
/// JSON keys are the camelCase property names and the encoder sorts keys, so the
/// on-disk file is byte-stable across writes (matching ``AppshotJSON``).
public struct AppshotSettings: Codable, Sendable, Equatable {
    /// Key codes for the global capture trigger. Defaults to left + right Option
    /// (`58`, `61`). Stored as the raw `CGKeyCode` (`UInt16`) values.
    public var triggerKey: [UInt16]

    /// Whether the capture "shutter" sound plays. Defaults to `true`.
    public var captureSound: Bool

    /// Whether a capture copies its appshot to the clipboard. Defaults to `false`.
    public var copyOnCapture: Bool

    /// Whether the permission onboarding flow has been completed. Defaults to `false`.
    public var onboardingCompleted: Bool

    /// What to launch on login / CLI start. Defaults to ``StartupMode/none``.
    public var startupMode: StartupMode

    /// Whether Sparkle automatically checks for and downloads updates. Defaults to `true`.
    public var autoUpdate: Bool

    /// Whether the app shows a Dock icon (activation policy `.regular`). When
    /// `false` the app runs as a menu-bar-only accessory. Defaults to `false`.
    public var showInDock: Bool

    /// Default Claude MCP registration scope (`"user"` or `"project"`). Defaults to `"user"`.
    public var mcpDefaultScope: String

    /// The last project directory used for project-scoped MCP registration, if any.
    public var mcpLastProjectDirectory: String?

    /// Bundle identifier of an app to send each hot-key capture to: after the
    /// capture lands on the clipboard, the app is activated and Cmd+V is
    /// synthesized so the appshot appears in its composer (e.g. Claude
    /// Desktop, `com.anthropic.claudefordesktop`). `nil` disables the step.
    public var postCaptureSendTarget: String?

    public init(
        triggerKey: [UInt16] = [58, 61],
        captureSound: Bool = true,
        copyOnCapture: Bool = false,
        onboardingCompleted: Bool = false,
        startupMode: StartupMode = .none,
        autoUpdate: Bool = true,
        showInDock: Bool = false,
        mcpDefaultScope: String = "user",
        mcpLastProjectDirectory: String? = nil,
        postCaptureSendTarget: String? = nil
    ) {
        self.triggerKey = triggerKey
        self.captureSound = captureSound
        self.copyOnCapture = copyOnCapture
        self.onboardingCompleted = onboardingCompleted
        self.startupMode = startupMode
        self.autoUpdate = autoUpdate
        self.showInDock = showInDock
        self.mcpDefaultScope = mcpDefaultScope
        self.mcpLastProjectDirectory = mcpLastProjectDirectory
        self.postCaptureSendTarget = postCaptureSendTarget
    }

    /// The factory defaults used for brand-new users / when no file exists.
    public static let defaults = AppshotSettings()

    // Decode tolerantly so a partial / future / partially-corrupt config.json
    // still loads: each field independently falls back to its default when it is
    // missing OR has the wrong type, so one malformed field never discards the
    // rest of the file. (`try?` swallows a type-mismatch throw per field; the
    // whole-file fallback in `AppshotSettingsStore.load()` still handles a file
    // that isn't valid JSON at all.)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppshotSettings.defaults
        triggerKey = (try? container.decodeIfPresent([UInt16].self, forKey: .triggerKey)) ?? defaults.triggerKey
        captureSound = (try? container.decodeIfPresent(Bool.self, forKey: .captureSound)) ?? defaults.captureSound
        copyOnCapture = (try? container.decodeIfPresent(Bool.self, forKey: .copyOnCapture)) ?? defaults.copyOnCapture
        onboardingCompleted = (try? container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)) ?? defaults.onboardingCompleted
        startupMode = (try? container.decodeIfPresent(StartupMode.self, forKey: .startupMode)) ?? defaults.startupMode
        autoUpdate = (try? container.decodeIfPresent(Bool.self, forKey: .autoUpdate)) ?? defaults.autoUpdate
        showInDock = (try? container.decodeIfPresent(Bool.self, forKey: .showInDock)) ?? defaults.showInDock
        mcpDefaultScope = (try? container.decodeIfPresent(String.self, forKey: .mcpDefaultScope)) ?? defaults.mcpDefaultScope
        mcpLastProjectDirectory = (try? container.decodeIfPresent(String.self, forKey: .mcpLastProjectDirectory)) ?? defaults.mcpLastProjectDirectory
        postCaptureSendTarget = (try? container.decodeIfPresent(String.self, forKey: .postCaptureSendTarget)) ?? defaults.postCaptureSendTarget
    }
}

// MARK: - String-keyed registry

/// An error raised when a string-keyed settings mutation fails validation.
public enum AppshotSettingsError: Error, CustomStringConvertible, Sendable {
    case unknownKey(String)
    case invalidValue(key: String, value: String, expected: String)

    public var description: String {
        switch self {
        case let .unknownKey(key):
            "Unknown setting key '\(key)'."
        case let .invalidValue(key, value, expected):
            "Invalid value '\(value)' for '\(key)': expected \(expected)."
        }
    }
}

/// A single entry in the string-keyed settings registry, used by a future
/// `config get/set/list/unset` CLI. `get` renders the current value as a string;
/// `set` parses + validates a string into the setting (throwing
/// ``AppshotSettingsError`` on bad input).
public struct AppshotSettingKey: Sendable {
    public let key: String
    public let get: @Sendable (AppshotSettings) -> String
    public let set: @Sendable (inout AppshotSettings, String) throws -> Void

    public init(
        key: String,
        get: @escaping @Sendable (AppshotSettings) -> String,
        set: @escaping @Sendable (inout AppshotSettings, String) throws -> Void
    ) {
        self.key = key
        self.get = get
        self.set = set
    }
}

public extension AppshotSettings {
    /// The ordered, string-keyed registry exposing settings for a `config`-style CLI.
    /// The order is the canonical listing order.
    static let registry: [AppshotSettingKey] = [
        AppshotSettingKey(
            key: "triggerKey",
            get: { $0.triggerKey.map(String.init).joined(separator: ",") },
            set: { settings, raw in settings.triggerKey = try parseTriggerKey(raw) }
        ),
        AppshotSettingKey(
            key: "captureSound",
            get: { String($0.captureSound) },
            set: { settings, raw in settings.captureSound = try parseBool(raw, key: "captureSound") }
        ),
        AppshotSettingKey(
            key: "copyOnCapture",
            get: { String($0.copyOnCapture) },
            set: { settings, raw in settings.copyOnCapture = try parseBool(raw, key: "copyOnCapture") }
        ),
        AppshotSettingKey(
            key: "onboardingCompleted",
            get: { String($0.onboardingCompleted) },
            set: { settings, raw in settings.onboardingCompleted = try parseBool(raw, key: "onboardingCompleted") }
        ),
        AppshotSettingKey(
            key: "startupMode",
            get: { $0.startupMode.rawValue },
            set: { settings, raw in settings.startupMode = try parseStartupMode(raw) }
        ),
        AppshotSettingKey(
            key: "autoUpdate",
            get: { String($0.autoUpdate) },
            set: { settings, raw in settings.autoUpdate = try parseBool(raw, key: "autoUpdate") }
        ),
        AppshotSettingKey(
            key: "showInDock",
            get: { String($0.showInDock) },
            set: { settings, raw in settings.showInDock = try parseBool(raw, key: "showInDock") }
        ),
        AppshotSettingKey(
            key: "mcpDefaultScope",
            get: { $0.mcpDefaultScope },
            set: { settings, raw in settings.mcpDefaultScope = try parseMCPScope(raw) }
        ),
        AppshotSettingKey(
            key: "mcpLastProjectDirectory",
            get: { $0.mcpLastProjectDirectory ?? "" },
            set: { settings, raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.mcpLastProjectDirectory = trimmed.isEmpty ? nil : trimmed
            }
        ),
        AppshotSettingKey(
            key: "postCaptureSendTarget",
            get: { $0.postCaptureSendTarget ?? "" },
            set: { settings, raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.postCaptureSendTarget = trimmed.isEmpty ? nil : trimmed
            }
        ),
    ]

    /// Looks up a registry entry by its string key.
    static func registryKey(_ key: String) -> AppshotSettingKey? {
        registry.first { $0.key == key }
    }

    // MARK: - Parsing helpers

    private static func parseBool(_ raw: String, key: String) throws -> Bool {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "on": true
        case "false", "no", "0", "off": false
        default:
            throw AppshotSettingsError.invalidValue(key: key, value: raw, expected: "a boolean (true/false)")
        }
    }

    private static func parseTriggerKey(_ raw: String) throws -> [UInt16] {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.isEmpty == false else {
            throw AppshotSettingsError.invalidValue(
                key: "triggerKey",
                value: raw,
                expected: "comma-separated key codes like \"58,61\""
            )
        }
        var codes: [UInt16] = []
        for part in parts {
            guard let code = UInt16(part) else {
                throw AppshotSettingsError.invalidValue(
                    key: "triggerKey",
                    value: raw,
                    expected: "comma-separated key codes like \"58,61\""
                )
            }
            codes.append(code)
        }
        return codes.sorted()
    }

    private static func parseStartupMode(_ raw: String) throws -> StartupMode {
        guard let mode = StartupMode(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
            throw AppshotSettingsError.invalidValue(
                key: "startupMode",
                value: raw,
                expected: "one of \(StartupMode.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return mode
    }

    private static func parseMCPScope(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard MCPScope(rawValue: trimmed) != nil else {
            throw AppshotSettingsError.invalidValue(
                key: "mcpDefaultScope",
                value: raw,
                expected: "one of \(MCPScope.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return trimmed
    }
}
