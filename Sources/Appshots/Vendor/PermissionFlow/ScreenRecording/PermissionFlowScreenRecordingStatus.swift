// Vendored from PermissionFlow (MIT). See Vendor/PermissionFlow/LICENSE.
#if os(macOS)
import Foundation

@available(macOS 13.0, *)
public enum PermissionFlowScreenRecordingStatus {
    @MainActor
    public static func register() {
        PermissionStatusRegistry.register(
            provider: ScreenRecordingPermissionStatusProvider(),
            for: .screenRecording
        )
    }
}
#endif