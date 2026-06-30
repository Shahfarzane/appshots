import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the GUI launch-at-login item.
///
/// The whole point of this type is to keep `ServiceManagement` (an app-only
/// framework) out of `AppshotsCore`, and to read the login-item status **live**
/// every time — `SMAppService` is the source of truth and is mutated out of band
/// by the user in System Settings > Login Items, so the status must never be
/// cached.
@MainActor
struct LoginItemController {
    /// The live status from `SMAppService.mainApp`. Read fresh on every access.
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Whether the app is registered to launch at login.
    var isEnabled: Bool {
        status == .enabled
    }

    /// Whether the user must approve the login item in System Settings.
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// Registers the app as a login item.
    func register() throws {
        try SMAppService.mainApp.register()
    }

    /// Unregisters the app login item.
    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
