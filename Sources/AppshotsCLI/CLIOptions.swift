import Foundation

/// Tiny shared argument helpers for the hand-rolled subcommand parsers. The
/// single home for value/flag lookups so `main.swift` and every command file
/// read flags the same way.
enum CLIOptions {
    /// The value following `name` (e.g. `--scope user` → `"user"`), or `nil`.
    static func string(_ arguments: [String], name: String) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    /// The integer value following `name`, or `nil` when absent or unparseable.
    static func integer(_ arguments: [String], name: String) -> Int? {
        string(arguments, name: name).flatMap { Int($0) }
    }

    /// The double value following `name`, or `nil` when absent or unparseable.
    static func double(_ arguments: [String], name: String) -> Double? {
        string(arguments, name: name).flatMap { Double($0) }
    }

    /// True when any of `names` is present (boolean/switch flags).
    static func flag(_ arguments: [String], _ names: String...) -> Bool {
        arguments.contains { names.contains($0) }
    }

    /// `--json`: emit machine-readable output instead of human text.
    static func wantsJSON(_ arguments: [String]) -> Bool {
        flag(arguments, "--json")
    }

    /// `--dry-run` / `-n`: preview a state change without applying it.
    static func isDryRun(_ arguments: [String]) -> Bool {
        flag(arguments, "--dry-run", "-n")
    }
}
