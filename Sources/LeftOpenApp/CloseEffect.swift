import AppKit

/// The "a port just closed" feedback: one sound, shared by the real close flow (`MenuModel`)
/// and the Settings preview button, so tuning it in one place tunes it everywhere.
@MainActor
enum CloseEffect {
    private static let soundURL = Bundle.module.url(forResource: "DoorClose", withExtension: "aiff")
    /// Sounds currently playing, kept alive until they finish (NSSound can cut off mid-playback
    /// if nothing retains it), then dropped once their duration has elapsed.
    private static var playingSounds: [UUID: NSSound] = [:]

    static func playSound() {
        guard AppSettings.shared.soundEffectsEnabled,
              let url = soundURL, let sound = NSSound(contentsOf: url, byReference: true) else { return }
        let id = UUID()
        playingSounds[id] = sound
        sound.play()
        Task {
            try? await Task.sleep(for: .seconds(sound.duration + 0.2))
            playingSounds[id] = nil
        }
    }
}
