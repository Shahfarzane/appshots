import AppKit
import AppshotsCore
import Observation
import SwiftUI

/// View model backing the MCP settings pane (`MCPSettingsPane`). Owns the
/// registrar interactions (status/environment/enable/disable/scope).
@MainActor
@Observable
final class MCPSettingsViewModel {
    var status: MCPStatus = .notEnabled
    var environment: MCPEnvironmentInfo?
    var scope: MCPScope = .user
    var projectDirectory: URL?
    var isRunning = false
    var lastError: String?

    @ObservationIgnored private let manager = ClaudeMCPRegistrar()
    @ObservationIgnored var onEnabled: (() -> Void)?

    func refresh() {
        guard !isRunning else { return }
        isRunning = true
        Task {
            await reload()
            isRunning = false
        }
    }

    func enable() {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        Task {
            do {
                switch scope {
                case .user:
                    try await manager.enableUser()
                case .project:
                    guard let directory = projectDirectory else {
                        throw MCPError.projectDirectoryMissing
                    }
                    try await manager.enableProject(directory: directory)
                }
            } catch {
                lastError = error.localizedDescription
            }
            await reload()
            isRunning = false
            if lastError == nil {
                switch status {
                case .enabledUser, .enabledProject:
                    onEnabled?()
                default:
                    break
                }
            }
        }
    }

    func disable() {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        Task {
            do {
                try await manager.disable(
                    scope: scope,
                    projectDirectory: scope == .project ? projectDirectory : nil
                )
            } catch {
                lastError = error.localizedDescription
            }
            await reload()
            isRunning = false
        }
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the project folder for the Claude Code .mcp.json"
        if let current = projectDirectory {
            panel.directoryURL = current
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectDirectory = url
        refresh()
    }

    private func reload() async {
        let environment = await manager.environment()
        let status = await manager.status(projectDirectory: scope == .project ? projectDirectory : nil)
        self.environment = environment
        self.status = status
    }
}
