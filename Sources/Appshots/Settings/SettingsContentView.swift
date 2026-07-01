import Luminare
import SwiftUI

/// The Loop-style settings layout: a divided stack with a grouped sidebar and a
/// detail pane. Modeled on Loop's `SettingsContentView` (minus the live-preview
/// inspector, which Appshots has no use for).
struct SettingsContentView: View {
    @Bindable var model: SettingsWindowModel
    /// The app model, injected into the environment so every pane can reach the
    /// capture/hotkey/sound/history state.
    let appModel: AppshotsModel

    @Environment(\.luminareTitleBarHeight) private var titleBarHeight

    var body: some View {
        LuminareDividedStack {
            LuminareSidebar {
                LuminareSidebarSection("Appshots", selection: $model.currentTab, items: SettingsTab.allTabs)
            }
            .frame(width: AppshotsTheme.Size.sidebarWidth)
            .padding(.top, titleBarHeight)
            .luminareBackground()

            LuminarePane {
                model.currentTab.view()
            } header: {
                HStack(spacing: AppshotsTheme.Spacing.sm) {
                    model.currentTab.icon
                    Text(model.currentTab.title)
                        .font(.appWindowTitle)
                    Spacer()
                }
            }
            // Constant width across every tab — switching destinations must
            // never resize the window.
            .frame(width: AppshotsTheme.Size.paneWidth)
        }
        .luminareTint(overridingWith: .accentColor)
        .ignoresSafeArea()
        .environment(appModel)
    }
}
