import SwiftUI

/// App entry point. Volume Rocker lives only in the menu bar (`LSUIElement`), so there is no Dock icon
/// and no main window, just the mixer panel and a separate Settings window.
@main
struct VolumeRockerApp: App {
    var body: some Scene {
        MenuBarExtra {
            MixerPanelView()
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .accessibilityLabel(Text("Volume Rocker"))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
