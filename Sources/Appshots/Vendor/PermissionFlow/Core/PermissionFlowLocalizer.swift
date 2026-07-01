// Vendored from PermissionFlow (MIT). See Vendor/PermissionFlow/LICENSE.
#if os(macOS)
import Foundation

@available(macOS 13.0, *)
enum PermissionFlowLocalizer {
    /// Returns the caller-supplied default value. The vendored copy ships
    /// without `.lproj` resources, so there is no localized bundle to consult;
    /// the signature is preserved so existing callers remain unaffected.
    static func string(
        _ key: String,
        defaultValue: String,
        localeIdentifier: String?
    ) -> String {
        defaultValue
    }
}
#endif