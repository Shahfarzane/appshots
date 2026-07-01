import SwiftUI

struct FooterUpdateButton: View {
    var state: AppshotsUpdateManager.UpdateState
    var status: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: iconName)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(state == .downloadingUpdate)
        .help(status)
    }

    private var title: String {
        switch state {
        case .checkForUpdate:
            "Updates"
        case .downloadingUpdate:
            "Downloading"
        case .installUpdate:
            "Install"
        }
    }

    private var iconName: String {
        switch state {
        case .checkForUpdate:
            "arrow.down.circle"
        case .downloadingUpdate:
            "arrow.down.circle.fill"
        case .installUpdate:
            "checkmark.circle.fill"
        }
    }
}
