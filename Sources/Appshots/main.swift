import AppKit
import AppshotsCore

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Honor the persisted Dock-visibility preference at launch: `.regular` shows a
// Dock icon, `.accessory` runs menu-bar-only (the default). The GUI toggles this
// live from Settings; see `AppshotsModel.applyDockVisibility`.
app.setActivationPolicy(AppshotSettingsStore().load().showInDock ? .regular : .accessory)
app.run()
