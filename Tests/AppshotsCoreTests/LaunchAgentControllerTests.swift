@testable import AppshotsCore
import Foundation
import Testing

/// Covers the pure plist-rendering half of ``LaunchAgentController`` (FIX D
/// regression). Never calls `install()`/`uninstall()` (those shell out to
/// `launchctl`); only `plistContents()` is exercised, against temp directories.
struct LaunchAgentControllerTests {
    @Test func `Plist renders the expected launchd job`() throws {
        let logDirectory = temporaryRootURL()
        defer { try? FileManager.default.removeItem(at: logDirectory) }
        let programPath = URL(fileURLWithPath: "/opt/appshots/appshotsctl")

        let controller = LaunchAgentController(
            launchAgentsDirectory: temporaryRootURL(),
            logDirectory: logDirectory,
            programPath: programPath
        )
        let plist = try controller.plistContents()
        let collapsed = plist.components(separatedBy: .whitespacesAndNewlines).joined()

        // Label.
        #expect(plist.contains("<string>ceo.nerd.appshots.cli.daemon</string>"))
        #expect(LaunchAgentController.label == "ceo.nerd.appshots.cli.daemon")

        // ProgramArguments: <program path> daemon.
        #expect(collapsed.contains(
            "<key>ProgramArguments</key><array><string>/opt/appshots/appshotsctl</string><string>daemon</string></array>"
        ))

        // RunAtLoad is a bare <true/>.
        #expect(collapsed.contains("<key>RunAtLoad</key><true/>"))

        // KeepAlive is a DICT with SuccessfulExit=false (NOT a bare <true/>).
        #expect(collapsed.contains(
            "<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>"
        ))
        #expect(!collapsed.contains("<key>KeepAlive</key><true/>"))

        // Log paths point at the injected log directory.
        #expect(plist.contains(controller.standardOutPath))
        #expect(plist.contains(controller.standardErrorPath))
        #expect(controller.standardOutPath.hasPrefix(logDirectory.path))
        #expect(controller.standardOutPath.hasSuffix("daemon.out.log"))
        #expect(controller.standardErrorPath.hasSuffix("daemon.err.log"))
    }

    @Test func `Plist rendering throws when the program path is unresolved`() {
        let controller = LaunchAgentController(
            launchAgentsDirectory: temporaryRootURL(),
            logDirectory: temporaryRootURL(),
            programPath: nil
        )
        #expect(throws: LaunchAgentError.self) {
            _ = try controller.plistContents()
        }
    }

    private func temporaryRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("appshots-launchagent-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
