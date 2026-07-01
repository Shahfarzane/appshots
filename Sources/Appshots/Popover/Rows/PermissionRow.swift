import SwiftUI

struct PermissionRow: View {
    var title: String
    var granted: Bool
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        HStack(spacing: AppshotsTheme.Spacing.sm) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.appSuccess : Color.appWarning)
            Text(title)
                .font(.appRowLabel)
            Spacer()
            if granted {
                Text("Allowed")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } else {
                Button(action: action) {
                    Text(actionTitle)
                        .padding(.horizontal, AppshotsTheme.Spacing.md)
                        .frame(height: 26)
                }
                .buttonStyle(.luminare)
                .luminareCornerRadius(AppshotsTheme.Radius.card)
                .fixedSize()
            }
        }
        .frame(minHeight: 34)
    }
}
