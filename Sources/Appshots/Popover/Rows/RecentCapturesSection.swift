import AppshotsCore
import SwiftUI

struct RecentCapturesSection: View {
    let model: AppshotsModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppshotsTheme.Spacing.xs) {
            Text("Recent Shots")
                .font(.appCaption)
                .foregroundStyle(.secondary)

            if model.pendingCapture != nil || model.recentCaptures.isEmpty == false {
                ScrollView {
                    LazyVStack(spacing: AppshotsTheme.Spacing.sm) {
                        if let pendingCapture = model.pendingCapture {
                            PendingCaptureCard(pendingCapture: pendingCapture)
                        }
                        ForEach(model.recentCaptures) { record in
                            AppshotRecordCard(record: record) {
                                model.openPreview?(record)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: 320)
            } else {
                Text("No appshots yet.")
                    .font(.appRowLabel)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
                    .modifier(PopoverCardBackground())
            }
        }
    }
}

private struct PendingCaptureCard: View {
    var pendingCapture: PendingCaptureViewState

    var body: some View {
        HStack(alignment: .top, spacing: AppshotsTheme.Spacing.md) {
            CaptureThumbnail(
                url: pendingCapture.screenshotURL,
                maxPixelSize: 160,
                width: AppshotsTheme.Size.popoverThumbnail.width,
                height: AppshotsTheme.Size.popoverThumbnail.height,
                cornerRadius: AppshotsTheme.Radius.thumbnail,
                placeholderFontSize: 13,
                showsBackground: true,
                showsBorder: false
            )

            VStack(alignment: .leading, spacing: AppshotsTheme.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: AppshotsTheme.Spacing.sm) {
                    Text(pendingCapture.appName)
                        .font(.appCardTitle)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    ProgressView()
                        .controlSize(.small)
                }

                Text(pendingCapture.windowTitle.isEmpty ? "Capturing window…" : pendingCapture.windowTitle)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(pendingCapture.screenshotURL == nil ? "Waiting for screenshot" : "Screenshot ready")
                    .font(.appCaptionSmall)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 1)
        }
        .padding(AppshotsTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PopoverCardBackground())
    }
}
