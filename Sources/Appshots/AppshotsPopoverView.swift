import AppshotsCore
import SwiftUI

struct AppshotsPopoverView: View {
    @Bindable var model: AppshotsModel
    private let updateManager = AppshotsUpdateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppshotsTheme.Spacing.md) {
            header
            permissionNotice
            PermissionsSection(model: model)
            RecentCapturesSection(model: model)
            footer
        }
        .padding(AppshotsTheme.Spacing.section)
        // Fixed width, height fits the content (the popover sizes to this).
        .frame(width: AppshotsTheme.Size.popover.width, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: AppshotsTheme.Spacing.md) {
            Image(systemName: "camera.viewfinder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: AppshotsTheme.Size.tabIcon, height: AppshotsTheme.Size.tabIcon)

            VStack(alignment: .leading, spacing: 1) {
                Text("Appshots")
                    .font(.appWindowTitle)
                Text(model.statusMessage)
                    .font(.appCaption)
                    .foregroundStyle(model.isCapturing ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var permissionNotice: some View {
        if model.permissionRequestState == .permissionsPending {
            HStack(alignment: .top, spacing: AppshotsTheme.Spacing.sm) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.appWarning)
                VStack(alignment: .leading, spacing: AppshotsTheme.Spacing.xxs) {
                    Text("Permissions Required")
                        .font(.appCardTitle)
                    Text("Grant both permissions, then capture again.")
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(AppshotsTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appWarningSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppshotsTheme.Radius.card))
        }
    }

    private var footer: some View {
        HStack(spacing: AppshotsTheme.Spacing.md) {
            Button {
                model.openSettings?()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Open Appshots settings")

            Spacer()

            FooterUpdateButton(
                state: updateManager.updateState,
                status: updateManager.statusText,
                action: updateManager.runPrimaryAction
            )

            Button {
                model.quit()
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Appshots")
        }
        .font(.appCaption)
        .tint(.secondary)
    }
}

/// Accessibility / Screen Recording status, as a titled card matching the
/// settings panes (only shown while something still needs granting).
private struct PermissionsSection: View {
    @Bindable var model: AppshotsModel

    var body: some View {
        if !model.hasAccessibilityPermission || !model.hasScreenRecordingPermission {
            VStack(alignment: .leading, spacing: AppshotsTheme.Spacing.xs) {
                Text("Permissions")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    PermissionRow(
                        title: "Accessibility",
                        granted: model.hasAccessibilityPermission,
                        actionTitle: "Grant",
                        action: model.requestAccessibilityPermission
                    )
                    Divider().opacity(0.4)
                    PermissionRow(
                        title: "Screen Recording",
                        granted: model.hasScreenRecordingPermission,
                        actionTitle: "Grant",
                        action: model.requestScreenRecordingPermission
                    )
                }
                .padding(.horizontal, AppshotsTheme.Spacing.md)
                .padding(.vertical, AppshotsTheme.Spacing.xs)
                .modifier(PopoverCardBackground())
            }
        }
    }
}
