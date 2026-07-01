import AppshotsCore
import Foundation

/// `appshotsctl onboarding status` — report the permission + onboarding state.
/// Reuses ``AppshotDoctor`` for the live Accessibility / Screen Recording checks
/// and reads `onboardingCompleted` from settings. Granting permissions stays a
/// system-level action; this only reports.
enum OnboardingCommand {
    static func run(arguments: [String], store: AppshotStore, settingsStore: AppshotSettingsStore) throws {
        let subcommand = arguments.first ?? "status"
        guard subcommand == "status" else {
            throw CLIError(
                message: "Unknown onboarding subcommand: \(subcommand)\nUsage: appshotsctl onboarding status",
                exitCode: 2
            )
        }

        let checks = AppshotDoctor.run(store: store)
        let accessibility = checks.first { $0.name == "accessibility_permission" }?.ok ?? false
        let screenRecording = checks.first { $0.name == "screen_recording_permission" }?.ok ?? false
        let completed = settingsStore.load().onboardingCompleted

        print("accessibility: \(accessibility ? "granted" : "not granted")")
        print("screen recording: \(screenRecording ? "granted" : "not granted")")
        print("onboarding completed: \(completed ? "yes" : "no")")
    }
}
