import CoreGraphics
import Foundation

/// One-way seeding of `config.json` from the GUI's legacy `UserDefaults`-backed
/// preferences. Runs once, only when no `config.json` exists yet: existing users
/// keep their trigger key / capture-sound / onboarding state, and brand-new users
/// get a defaults file written so the store always has a canonical source.
///
/// The legacy `UserDefaults` keys are never deleted — migration is strictly
/// read-only against them.
public enum AppshotSettingsMigration {
    /// The GUI app's preferences domain (its bundle identifier).
    private static let legacySuiteName = "ceo.nerd.appshots"

    static let triggerKeyDefaultsKey = "AppshotsTriggerKey"
    static let legacyHotKeyDefaultsKey = "AppshotsHotKey"
    static let captureSoundDefaultsKey = "appshots.captureSound.enabled"
    static let onboardingDefaultsKey = "appshots.onboarding.hasCompleted"

    /// Seeds `config.json` from legacy defaults when it is absent; a no-op once a
    /// config file exists.
    public static func seedIfNeeded(store: AppshotSettingsStore) {
        guard store.fileExists == false else { return }

        let settings = migratedSettings()
        do {
            // Re-checks existence inside the config.lock critical section: a
            // concurrent writer (e.g. `appshotsctl config set` racing first GUI
            // launch) may have created the file since the unlocked check above.
            if try store.seedIfAbsent(settings) {
                AppLog.store.notice("seeded config.json at \(store.configURL.path, privacy: .public)")
            }
        } catch {
            AppLog.store.error("failed to seed config.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Builds the initial settings, overlaying any legacy preferences onto the defaults.
    static func migratedSettings(defaults: UserDefaults? = legacyDefaults()) -> AppshotSettings {
        var settings = AppshotSettings.defaults
        guard let defaults else { return settings }

        if let triggerKey = legacyTriggerKey(from: defaults) {
            settings.triggerKey = triggerKey
        }
        // Capture sound: absent legacy key means enabled (the existing semantics),
        // so only override the `true` default when the key was explicitly written.
        if defaults.object(forKey: captureSoundDefaultsKey) != nil {
            settings.captureSound = defaults.bool(forKey: captureSoundDefaultsKey)
        }
        settings.onboardingCompleted = defaults.bool(forKey: onboardingDefaultsKey)
        return settings
    }

    /// Reads the legacy trigger key, falling back to the `AppshotsHotKey` enum
    /// decode path so users on the oldest persisted format still migrate cleanly.
    private static func legacyTriggerKey(from defaults: UserDefaults) -> [UInt16]? {
        if let raw = defaults.string(forKey: triggerKeyDefaultsKey),
           let data = raw.data(using: .utf8),
           let codes = try? JSONDecoder().decode([CGKeyCode].self, from: data) {
            return codes.map { UInt16($0) }.sorted()
        }
        if let legacy = defaults.string(forKey: legacyHotKeyDefaultsKey) {
            return AppshotsHotKey.decode(from: legacy).triggerKeyCodes.map { UInt16($0) }.sorted()
        }
        return nil
    }

    /// The GUI domain to read legacy keys from. Opening the suite reads the GUI's
    /// preferences cross-process (e.g. from the CLI); when that is unavailable
    /// (in-process, where the suite name equals the running app's own bundle id),
    /// it falls back to the standard defaults, which are that same domain.
    private static func legacyDefaults() -> UserDefaults? {
        UserDefaults(suiteName: legacySuiteName) ?? .standard
    }
}
