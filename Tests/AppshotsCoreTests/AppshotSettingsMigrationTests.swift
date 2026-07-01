@testable import AppshotsCore
import Foundation
import Testing

/// Covers ``AppshotSettingsMigration`` seeding. The absent/default and idempotent
/// paths exercise `seedIfNeeded` against a temp-root store; the legacy-overlay
/// path uses the injectable `migratedSettings(defaults:)` seam with a throwaway
/// `UserDefaults` suite (never the real GUI domain or `~/.appshots`).
struct AppshotSettingsMigrationTests {
    @Test func `Seed writes a defaults config when none exists`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotSettingsStore(rootURL: rootURL)
        #expect(store.fileExists == false)

        AppshotSettingsMigration.seedIfNeeded(store: store)

        // `seedIfNeeded` writes a canonical config.json. Its migration-controlled
        // fields (trigger key / capture sound / onboarding) are read from the real
        // hardcoded GUI `UserDefaults` suite, so this path only asserts the file is
        // created and reloads consistently; the legacy-overlay values are covered
        // deterministically via the injectable `migratedSettings(defaults:)` seam
        // below. (Note: `seedIfNeeded` is hardcoded to the real suite — no injection
        // seam — so its exact field values are not asserted here.)
        #expect(store.fileExists)
        #expect(store.load() == store.load())
    }

    @Test func `Seed is a no-op when config already exists`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotSettingsStore(rootURL: rootURL)
        var existing = AppshotSettings.defaults
        existing.triggerKey = [10, 11]
        existing.captureSound = false
        existing.startupMode = .gui
        try store.save(existing)

        AppshotSettingsMigration.seedIfNeeded(store: store)

        // Existing file is left untouched (not overwritten with defaults).
        #expect(store.load() == existing)
    }

    @Test func `Migrated settings overlay legacy trigger key and capture sound`() throws {
        let suiteName = "appshots-migration-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("[10,11]", forKey: AppshotSettingsMigration.triggerKeyDefaultsKey)
        defaults.set(false, forKey: AppshotSettingsMigration.captureSoundDefaultsKey)
        defaults.set(true, forKey: AppshotSettingsMigration.onboardingDefaultsKey)

        let migrated = AppshotSettingsMigration.migratedSettings(defaults: defaults)

        #expect(migrated.triggerKey == [10, 11])
        #expect(migrated.captureSound == false)
        #expect(migrated.onboardingCompleted == true)
        // Untouched legacy fields keep their defaults.
        #expect(migrated.autoUpdate == AppshotSettings.defaults.autoUpdate)
        #expect(migrated.startupMode == AppshotSettings.defaults.startupMode)
    }

    @Test func `Absent legacy capture-sound key keeps the enabled default`() throws {
        let suiteName = "appshots-migration-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Only a trigger key written; capture sound key is absent.
        defaults.set("[58,61]", forKey: AppshotSettingsMigration.triggerKeyDefaultsKey)

        let migrated = AppshotSettingsMigration.migratedSettings(defaults: defaults)
        #expect(migrated.captureSound == true)
        #expect(migrated.triggerKey == [58, 61])
    }

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("appshots-migration-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
