// Vendored from PermissionFlow (MIT). See Vendor/PermissionFlow/LICENSE.
#if os(macOS)
import AVFoundation
import Foundation

@available(macOS 13.0, *)
public struct ScreenRecordingPermissionStatusProvider: PermissionStatusProviding {
    public var capability: PermissionStatusCapability { .preflightSupported }

    public func authorizationState() -> PermissionAuthorizationState {
        let isGranted = CGPreflightScreenCaptureAccess()
        return isGranted ? .granted : .notGranted
    }

    public init() {}
}
#endif