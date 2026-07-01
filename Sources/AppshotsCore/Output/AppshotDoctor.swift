import ApplicationServices
import CoreGraphics
import Foundation

/// A single Appshots health check result. Encodes to the same `{detail, name, ok}`
/// JSON shape the CLI `doctor` command and the `doctor_appshots` MCP tool emit.
public struct AppshotHealthCheck: Codable {
    public var name: String
    public var ok: Bool
    public var detail: String

    public init(name: String, ok: Bool, detail: String) {
        self.name = name
        self.ok = ok
        self.detail = detail
    }
}

/// Shared health-check runner used by both the CLI `doctor` command and the
/// `doctor_appshots` MCP tool. The check list, names, detail strings, predicates,
/// and order are the wire contract — keep them identical across both call sites.
public enum AppshotDoctor {
    public static func run(store: AppshotStore) -> [AppshotHealthCheck] {
        let latest = store.latestCapture()
        return [
            AppshotHealthCheck(name: "accessibility_permission", ok: AXIsProcessTrusted(), detail: "System Settings > Privacy & Security > Accessibility"),
            AppshotHealthCheck(name: "screen_recording_permission", ok: CGPreflightScreenCaptureAccess(), detail: "System Settings > Privacy & Security > Screen & System Audio Recording"),
            AppshotHealthCheck(name: "storage_root", ok: FileManager.default.fileExists(atPath: store.rootURL.path), detail: store.rootURL.path),
            AppshotHealthCheck(name: "index", ok: FileManager.default.fileExists(atPath: store.indexURL.path), detail: store.indexURL.path),
            AppshotHealthCheck(name: "latest_capture", ok: latest != nil, detail: latest?.id ?? "none"),
            AppshotHealthCheck(name: "latest_prompt", ok: latest.map { FileManager.default.fileExists(atPath: $0.appshotTextPath) } ?? false, detail: latest?.appshotTextPath ?? "none"),
            AppshotHealthCheck(name: "latest_screenshot", ok: latest?.screenshotPath.map(FileManager.default.fileExists(atPath:)) ?? false, detail: latest?.screenshotPath ?? "none"),
        ]
    }
}
