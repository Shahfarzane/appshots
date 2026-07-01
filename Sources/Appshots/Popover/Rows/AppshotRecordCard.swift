import AppshotsCore
import SwiftUI

struct AppshotRecordCard: View {
    var record: AppshotRecord
    var openAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: openAction) {
            HStack(alignment: .center, spacing: AppshotsTheme.Spacing.md) {
                CaptureThumbnail(
                    url: record.screenshotURL,
                    maxPixelSize: 160,
                    width: AppshotsTheme.Size.popoverThumbnail.width,
                    height: AppshotsTheme.Size.popoverThumbnail.height,
                    cornerRadius: AppshotsTheme.Radius.thumbnail,
                    placeholderFontSize: 13,
                    showsBackground: true,
                    showsBorder: false
                )

                // App name, plus the window title when the capture had one — no
                // date/time (that lives in the History grid tooltip + Preview).
                VStack(alignment: .leading, spacing: AppshotsTheme.Spacing.xxs) {
                    Text(record.appName)
                        .font(.appCardTitle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if record.windowTitle.isEmpty == false {
                        Text(record.windowTitle)
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(AppshotsTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(PopoverCardBackground(isHovering: isHovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open preview")
    }
}

/// The shared subtle-surface card used across the popover, matching the History
/// rows in the settings window.
struct PopoverCardBackground: ViewModifier {
    var isHovering: Bool = false

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: AppshotsTheme.Radius.card)
                .fill(isHovering ? Color.appSurfaceSelected : Color.appSurfaceSubtle)
                .overlay {
                    RoundedRectangle(cornerRadius: AppshotsTheme.Radius.card)
                        .strokeBorder(Color.appBorderSubtle, lineWidth: 1)
                }
        }
    }
}
