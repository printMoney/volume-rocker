import SwiftUI

/// Picks the SF Symbol for a volume level, like the system's own volume icon.
enum VolumeSymbol {
    static func name(volume: Float, isMuted: Bool) -> String {
        if isMuted || volume <= 0.001 {
            return "speaker.slash.fill"
        }
        if volume < 0.34 {
            return "speaker.wave.1.fill"
        }
        if volume < 0.67 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }
}
