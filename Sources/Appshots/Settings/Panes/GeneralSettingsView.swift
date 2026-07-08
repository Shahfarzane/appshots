import AppshotsCore
import Luminare
import SwiftUI
import UniformTypeIdentifiers

/// The merged General settings pane: Trigger Key, Permissions, and Sounds on a
/// single screen (replacing the separate Hotkeys/Sounds tabs). The trigger key
/// uses Loop's keybind recorder (`TriggerKeycorder`).
struct GeneralSettingsView: View {
    @Environment(AppshotsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        LuminareForm {
            TriggerKeyConfigurationView(triggerKey: $model.triggerKey) { recording in
                // Pause the global hot-key monitor while recording so the
                // keypress doesn't also fire a capture.
                model.setHotKeyMonitorActive?(!recording)
            }

            LuminareSection("Permissions") {
                PermissionComposeRow(
                    title: "Accessibility",
                    granted: model.hasAccessibilityPermission,
                    action: model.requestAccessibilityPermission
                )
                PermissionComposeRow(
                    title: "Screen Recording",
                    granted: model.hasScreenRecordingPermission,
                    action: model.requestScreenRecordingPermission
                )
            }

            LuminareSection("Sounds") {
                LuminareToggle("Play a sound when you capture", isOn: $model.playsCaptureSound)
            }

            LuminareSection("Options") {
                LuminareToggle("Show in Dock", isOn: $model.showInDock)

                // Codex-style handoff: after a hot-key capture, activate the
                // chosen app and paste the appshot into its composer. Styled
                // like the MCP scope row: Luminare buttons, active highlighted.
                LuminareCompose {
                    HStack(spacing: 8) {
                        sendTargetButton("Off", target: nil)
                        sendTargetButton("Claude Desktop", target: PostCaptureSender.claudeDesktopBundleID)

                        Button {
                            chooseSendTargetApp()
                        } label: {
                            Text(customSendTarget.map(displayName(forBundleID:)) ?? "Other…")
                                .fontWeight(customSendTarget != nil ? .semibold : .regular)
                                .frame(height: 32)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.luminare(tinted: customSendTarget != nil))
                        .luminareCornerRadius(8)
                        .fixedSize()
                        .tint(.accentColor)
                    }
                } label: {
                    Text("Send to")
                }
            }

            LuminareSection("Startup") {
                LuminareToggle("Launch at Login", isOn: $model.launchAtLogin)

                if model.loginItemRequiresApproval {
                    LuminareCompose {
                        Button { model.openLoginItemsSettings() } label: {
                            Text("Open Login Items")
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                        }
                        .buttonStyle(.luminare)
                        .luminareCornerRadius(8)
                        .fixedSize()
                    } label: {
                        Text("Approve Appshots in System Settings > Login Items to finish enabling.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            model.refreshPermissions()
            model.refreshStartupStatus()
        }
    }

    // MARK: - Send-capture-to picker

    /// The configured target when it isn't one of the built-in options, so the
    /// "Other…" button can show the chosen app's name highlighted.
    private var customSendTarget: String? {
        guard let target = model.postCaptureSendTarget,
              target != PostCaptureSender.claudeDesktopBundleID
        else {
            return nil
        }
        return target
    }

    /// A fixed-choice segment button. The active target renders with a filled
    /// accent tint (not just a hover highlight) so the current selection is
    /// unmistakable at rest.
    private func sendTargetButton(_ title: String, target: String?) -> some View {
        let isSelected = model.postCaptureSendTarget == target && customSendTarget == nil
        return Button {
            model.postCaptureSendTarget = target
        } label: {
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(height: 32)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.luminare(tinted: isSelected))
        .luminareCornerRadius(8)
        .fixedSize()
        .tint(.accentColor)
    }

    /// Picks an app bundle from /Applications and stores its bundle identifier.
    /// Cancel leaves the current selection untouched.
    private func chooseSendTargetApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = "Choose the app each capture is sent to"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else {
            return
        }
        model.postCaptureSendTarget = bundleID
    }

    private func displayName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}

/// A permission status row: granted shows a green checkmark; otherwise a Grant
/// button. Loop-styled (no default macOS button chrome).
private struct PermissionComposeRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LuminareCompose {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
                    .labelStyle(.titleAndIcon)
            } else {
                Button { action() } label: {
                    Text("Grant")
                        .frame(height: 32)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.luminare)
                .luminareCornerRadius(8)
                .fixedSize()
            }
        } label: {
            Text(title)
        }
    }
}
