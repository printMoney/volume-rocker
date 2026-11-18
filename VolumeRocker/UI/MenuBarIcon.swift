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

/// The menu bar icon, reflecting the current output volume and mute state.
struct MenuBarIcon: View {
    let output: OutputDeviceController

    var body: some View {
        Image(systemName: VolumeSymbol.name(volume: output.volume, isMuted: output.isMuted))
            .accessibilityLabel(Text("Volume Rocker"))
            .accessibilityValue(output.isMuted ? Text("Muted") : Text(output.volume, format: .percent.precision(.fractionLength(0))))
    }
}
