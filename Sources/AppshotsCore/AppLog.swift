import Foundation
import os

/// Central unified-logging facade for Appshots.
///
/// Every log line — from the `Appshots` menu-bar app, the `appshotsctl`
/// CLI/MCP server, and `AppshotsCore` — flows through Apple's unified logging
/// system (`os.Logger`) under one subsystem, so the whole system can be read
/// with a single predicate. Unlike `print`/stdout, this is safe inside the MCP
/// stdio loop because it never touches the JSON-RPC stream.
///
/// Read everything live:
///
///     log stream --predicate 'subsystem == "ceo.nerd.appshots"' --level debug
///
/// Dump the last few minutes of a past run (includes info + debug levels):
///
///     log show --last 10m --predicate 'subsystem == "ceo.nerd.appshots"' --info --debug
///
/// Narrow to one area, e.g. the capture pipeline:
///
///     log stream --predicate 'subsystem == "ceo.nerd.appshots" AND category == "capture"' --level debug
///
/// Levels used across the codebase:
/// - `.debug`   verbose tracing (only shown with `--level debug`)
/// - `.info`    routine detail
/// - `.notice`  normal milestones (default-visible)
/// - `.error`   recoverable failures
/// - `.fault`   unexpected, likely-buggy conditions
public enum AppLog {
    /// Unified-logging subsystem shared by every Appshots target. Matches the
    /// app bundle identifier so Console.app groups app and library logs together.
    public static let subsystem = "ceo.nerd.appshots"

    /// App startup, session, status-item, and hot-key lifecycle.
    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")

    /// The capture pipeline: frontmost target, capture phases, and outcomes.
    public static let capture = Logger(subsystem: subsystem, category: "capture")

    /// On-disk appshot store: saves, deletes, and index updates.
    public static let store = Logger(subsystem: subsystem, category: "store")

    /// MCP / JSON-RPC server requests and tool calls.
    public static let mcp = Logger(subsystem: subsystem, category: "mcp")

    /// Accessibility and screen-recording permission state.
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")

    /// Sparkle update checks and relaunch.
    public static let updates = Logger(subsystem: subsystem, category: "updates")

    /// Launch-at-login wiring: SMAppService login item and the launchd LaunchAgent.
    public static let startup = Logger(subsystem: subsystem, category: "startup")
}
