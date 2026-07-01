import AVFoundation
import AppshotsCore
import Foundation

/// Plays the short capture "shutter" sound that accompanies the appshot flight animation,
/// mirroring Codex's `Appshot.wav`. The player is preloaded and rewound on each capture so
/// rapid successive captures retrigger cleanly with minimal latency.
///
/// The asset ships in the app bundle's `Contents/Resources/Appshot.wav` (wired through both
/// `project.yml` and `scripts/build-app.sh`). When running outside a real `.app` (e.g. a raw
/// `swift run`), the resource is absent and playback is a no-op.
@MainActor
final class AppshotSoundPlayer {
    static let shared = AppshotSoundPlayer()

    /// Whether the capture sound is enabled. Backed by the shared settings store
    /// (`config.json`), defaulting to `true` when never set.
    nonisolated static var isEnabled: Bool {
        AppshotSettingsStore().load().captureSound
    }

    nonisolated static func setEnabled(_ enabled: Bool) {
        do {
            try AppshotSettingsStore().mutate { $0.captureSound = enabled }
        } catch {
            AppLog.store.error("failed to persist capture sound setting: \(error.localizedDescription, privacy: .public)")
        }
    }

    private let player: AVAudioPlayer?

    private init() {
        guard let url = Bundle.main.url(forResource: "Appshot", withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            self.player = nil
            return
        }
        player.prepareToPlay()
        self.player = player
    }

    /// Plays the capture sound from the start, unless muted in settings. Safe to call when the asset
    /// is missing.
    func playCapture() {
        guard Self.isEnabled, let player else { return }
        player.currentTime = 0
        player.play()
    }
}
