import Luminare
import SwiftUI

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
