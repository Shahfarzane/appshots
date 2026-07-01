import AppshotsCore
import Luminare
import SwiftUI

/// MCP settings, re-skinned onto Luminare. Reuses `MCPSettingsViewModel`
/// verbatim — only the chrome changes from the old floating utility window.
struct MCPSettingsPane: View {
    @State private var model = MCPSettingsViewModel()

    var body: some View {
        LuminareForm {
            LuminareSection {
                Text("Register Appshots as a Model Context Protocol server so Claude Code can read your captures.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }

            LuminareSection("Status") {
                LuminareCompose {
                    HStack(spacing: AppshotsTheme.Spacing.sm) {
                        if model.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Button { model.refresh() } label: {
                            Text("Refresh")
                                .frame(height: 32)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.luminare)
                        .luminareCornerRadius(8)
                        .fixedSize()
                        .disabled(model.isRunning)
                    }
                } label: {
                    HStack(spacing: AppshotsTheme.Spacing.sm) {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: AppshotsTheme.Size.statusDot, height: AppshotsTheme.Size.statusDot)
                        Text(badgeText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            LuminareSection("Scope") {
                LuminareCompose {
                    // Two Luminare buttons (like Disable/Enable), sized to fit the
                    // row; the active scope is shown highlighted.
                    HStack(spacing: 8) {
                        ForEach(MCPScope.allCases, id: \.self) { scope in
                            Button {
                                model.scope = scope
                            } label: {
                                Text(scope.displayName)
                                    .frame(height: 32)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(.luminare(overrideIsHovering: model.scope == scope))
                            .luminareCornerRadius(8)
                            .fixedSize()
                            .disabled(model.isRunning)
                        }
                    }
                    .onChange(of: model.scope) { _, _ in model.refresh() }
                } label: {
                    Text("Install for")
                }

                if model.scope == .project {
                    LuminareCompose {
                        Button { model.chooseProjectFolder() } label: {
                            Text("Choose…")
                                .frame(height: 32)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.luminare)
                        .luminareCornerRadius(8)
                        .fixedSize()
                        .disabled(model.isRunning)
                    } label: {
                        Text(model.projectDirectory?.path ?? "No folder selected")
                            .font(.caption)
                            .foregroundStyle(model.projectDirectory == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            LuminareSection("Environment") {
                environmentRow(
                    ok: model.environment?.claudeFound ?? false,
                    okText: "Claude Code CLI found",
                    badText: "Claude Code CLI not found",
                    detail: model.environment?.claudePath
                )
                environmentRow(
                    ok: model.environment?.helperExists ?? false,
                    okText: "Bundled helper found",
                    badText: "Bundled helper missing",
                    detail: model.environment?.helperPath
                )
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }

            LuminareSection {
                LuminareButtonRow {
                    Button("Disable") { model.disable() }
                        .disabled(model.isRunning || !canDisable)

                    Button("Enable") { model.enable() }
                        .disabled(model.isRunning || !canEnable)
                }
            }
        }
        .onAppear { model.refresh() }
    }

    private func environmentRow(ok: Bool, okText: String, badText: String, detail: String?) -> some View {
        LuminareCompose {
            EmptyView()
        } label: {
            HStack(alignment: .top, spacing: AppshotsTheme.Spacing.sm) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? Color.appSuccess : Color.appWarning)
                VStack(alignment: .leading, spacing: AppshotsTheme.Spacing.hairline) {
                    Text(ok ? okText : badText)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var canEnable: Bool {
        guard model.environment?.claudeFound ?? false else { return false }
        guard model.environment?.helperExists ?? false else { return false }
        if model.scope == .project { return model.projectDirectory != nil }
        return true
    }

    private var canDisable: Bool {
        model.environment?.claudeFound ?? false
    }

    private var badgeColor: Color {
        switch model.status {
        case .notEnabled: Color.appStatusInactive
        case .enabledUser, .enabledProject: Color.appSuccess
        case .error: Color.appDestructive
        }
    }

    private var badgeText: String {
        switch model.status {
        case .notEnabled:
            "Not enabled"
        case .enabledUser:
            "Enabled (user)"
        case let .enabledProject(path):
            path.isEmpty ? "Enabled (project)" : "Enabled (project: \(path))"
        case let .error(message):
            message
        }
    }
}
