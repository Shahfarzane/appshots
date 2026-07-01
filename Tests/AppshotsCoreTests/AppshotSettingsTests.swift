@testable import AppshotsCore
import Foundation
import Testing

/// Covers ``AppshotSettings`` (Codable + tolerant decode + string-keyed registry)
/// and ``AppshotSettingsStore`` round-tripping. Every test uses a unique temp root
/// so it never touches the real `~/.appshots/config.json`.
struct AppshotSettingsTests {
    // MARK: - Round-trip & defaults

    @Test func `Store round-trips saved settings`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotSettingsStore(rootURL: rootURL)
        var settings = AppshotSettings.defaults
        settings.triggerKey = [10, 11]
        settings.captureSound = false
        settings.copyOnCapture = true
        settings.onboardingCompleted = true
        settings.startupMode = .headless
        settings.autoUpdate = false
        settings.showInDock = true
        settings.mcpDefaultScope = "project"
        settings.mcpLastProjectDirectory = "/tmp/project"

        try store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func `Load returns defaults when file absent`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotSettingsStore(rootURL: rootURL)
        #expect(store.fileExists == false)
        #expect(store.load() == AppshotSettings.defaults)
    }

    @Test func `Config URL ends in config.json under the root`() {
        let rootURL = temporaryRootURL()
        let store = AppshotSettingsStore(rootURL: rootURL)
        #expect(store.configURL.lastPathComponent == "config.json")
        #expect(store.configURL.deletingLastPathComponent().path == rootURL.path)
    }

    // MARK: - Registry validation (valid set)

    @Test func `Registry parses trigger key into sorted codes`() throws {
        var settings = AppshotSettings.defaults
        try setRegistry("triggerKey", "58,61", into: &settings)
        #expect(settings.triggerKey == [58, 61])

        try setRegistry("triggerKey", "61, 58", into: &settings)
        #expect(settings.triggerKey == [58, 61])
    }

    @Test func `Registry parses every accepted boolean spelling`() throws {
        let truthy = ["true", "yes", "on", "1"]
        let falsy = ["false", "no", "off", "0"]
        for raw in truthy {
            var settings = AppshotSettings.defaults
            try setRegistry("captureSound", raw, into: &settings)
            #expect(settings.captureSound == true, "\(raw) should parse true")
        }
        for raw in falsy {
            var settings = AppshotSettings.defaults
            try setRegistry("captureSound", raw, into: &settings)
            #expect(settings.captureSound == false, "\(raw) should parse false")
        }
    }

    @Test func `Registry parses every startup mode`() throws {
        for mode in StartupMode.allCases {
            var settings = AppshotSettings.defaults
            try setRegistry("startupMode", mode.rawValue, into: &settings)
            #expect(settings.startupMode == mode)
        }
    }

    @Test func `Registry parses both MCP scopes`() throws {
        for scope in ["user", "project"] {
            var settings = AppshotSettings.defaults
            try setRegistry("mcpDefaultScope", scope, into: &settings)
            #expect(settings.mcpDefaultScope == scope)
        }
    }

    @Test func `Registry get reflects current values`() throws {
        var settings = AppshotSettings.defaults
        settings.triggerKey = [58, 61]
        settings.startupMode = .gui
        #expect(AppshotSettings.registryKey("triggerKey")?.get(settings) == "58,61")
        #expect(AppshotSettings.registryKey("startupMode")?.get(settings) == "gui")
        #expect(AppshotSettings.registryKey("captureSound")?.get(settings) == "true")
    }

    // MARK: - Registry validation (invalid set throws)

    @Test func `Registry rejects a non-numeric trigger key`() {
        var settings = AppshotSettings.defaults
        #expect(throws: AppshotSettingsError.self) {
            try setRegistry("triggerKey", "x", into: &settings)
        }
    }

    @Test func `Registry rejects an unknown startup mode`() {
        var settings = AppshotSettings.defaults
        #expect(throws: AppshotSettingsError.self) {
            try setRegistry("startupMode", "bogus", into: &settings)
        }
    }

    @Test func `Registry rejects a non-boolean value`() {
        var settings = AppshotSettings.defaults
        #expect(throws: AppshotSettingsError.self) {
            try setRegistry("captureSound", "maybe", into: &settings)
        }
    }

    @Test func `Registry rejects an unknown MCP scope`() {
        var settings = AppshotSettings.defaults
        #expect(throws: AppshotSettingsError.self) {
            try setRegistry("mcpDefaultScope", "global", into: &settings)
        }
    }

    @Test func `Registry lookup returns nil for an unknown key`() {
        // Unknown keys are surfaced as a nil lookup (no registry entry); there is
        // no throwing set path because there is nothing to set.
        #expect(AppshotSettings.registryKey("notARealKey") == nil)
    }

    // MARK: - Tolerant decode (FIX C regression)

    @Test func `One mistyped field falls back to its default while others are preserved`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        // triggerKey has the wrong JSON type (number, not array); the other three
        // are valid and explicitly differ from their defaults.
        let json = #"{"triggerKey":5,"captureSound":false,"startupMode":"headless","copyOnCapture":true}"#
        let store = AppshotSettingsStore(rootURL: rootURL)
        try Data(json.utf8).write(to: store.configURL)

        let loaded = store.load()
        // Mistyped field -> default.
        #expect(loaded.triggerKey == AppshotSettings.defaults.triggerKey)
        // Valid sibling fields are preserved (NOT reset to defaults).
        #expect(loaded.captureSound == false)
        #expect(loaded.startupMode == .headless)
        #expect(loaded.copyOnCapture == true)
        // Absent fields still take their defaults.
        #expect(loaded.autoUpdate == AppshotSettings.defaults.autoUpdate)
        #expect(loaded.showInDock == AppshotSettings.defaults.showInDock)
    }

    @Test func `A non-JSON file loads as full defaults`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let store = AppshotSettingsStore(rootURL: rootURL)
        try Data("this is not json {{{".utf8).write(to: store.configURL)

        #expect(store.load() == AppshotSettings.defaults)
    }

    // MARK: - Startup mode persistence

    @Test func `Startup mode round-trips through the store via the registry`() throws {
        let rootURL = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AppshotSettingsStore(rootURL: rootURL)
        try store.mutate { settings in
            try setRegistry("startupMode", "headless", into: &settings)
        }
        #expect(store.load().startupMode == .headless)

        // A second store instance over the same root reads the persisted value.
        let reopened = AppshotSettingsStore(rootURL: rootURL)
        #expect(reopened.load().startupMode == .headless)
    }

    // MARK: - Helpers

    private func setRegistry(_ key: String, _ raw: String, into settings: inout AppshotSettings) throws {
        let entry = try #require(AppshotSettings.registryKey(key))
        try entry.set(&settings, raw)
    }

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("appshots-settings-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
