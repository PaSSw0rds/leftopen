import AppKit

/// Door sound effects: door open (port appeared) and door close (port closed).
/// Shared by the MenuModel state tracking and SettingsView preview, so tuning happens
/// in one place.
@MainActor
enum DoorSound {
    case doorOpen
    case doorClose

    private var soundURL: URL? {
        let resource = switch self {
        case .doorOpen: "DoorOpen"
        case .doorClose: "DoorClose"
        }
        return Bundle.module.url(forResource: resource, withExtension: "aiff")
    }

    /// Sounds currently playing, kept alive until they finish (NSSound can cut off mid-playback
    /// if nothing retains it), then dropped once their duration has elapsed.
    private static var playingSounds: [UUID: NSSound] = [:]

    func play() {
        guard AppSettings.shared.soundEffectsEnabled,
              let url = soundURL, let sound = NSSound(contentsOf: url, byReference: true) else { return }
        sound.volume = Float(AppSettings.shared.soundVolume)
        let id = UUID()
        DoorSound.playingSounds[id] = sound
        sound.play()
        Task {
            try? await Task.sleep(for: .seconds(sound.duration + 0.2))
            DoorSound.playingSounds[id] = nil
        }
    }
}

// Backward compatibility
@MainActor
enum CloseEffect {
    static func playSound() {
        DoorSound.doorClose.play()
    }
}
