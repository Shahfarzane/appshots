import Observation
import SwiftUI

/// Holds the selected settings destination. Mirrors the role of Loop's
/// `SettingsWindowManager.currentTab`, kept minimal for Appshots.
@MainActor
@Observable
final class SettingsWindowModel {
    var currentTab: SettingsTab = .history
}
