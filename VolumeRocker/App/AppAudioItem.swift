import AppKit
import CoreAudio
import Observation

/// One row in the mixer: an app (with all its helper processes) and its volume settings.
@MainActor
@Observable
final class AppAudioItem: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let isRegularApp: Bool

    private(set) var volume: Float
    private(set) var isMuted: Bool
    private(set) var equalizer: [Float]?
    private(set) var routedDeviceUID: String?
    private(set) var isPlaying = false
    /// When the app last stopped playing, or nil if it hasn't played since Volume Rocker started.
    private(set) var stoppedPlayingAt: Date?

    @ObservationIgnored var processObjectIDs: [AudioObjectID] = []
    @ObservationIgnored var outputDeviceID: AudioDeviceID?
    /// The output device whose saved settings are applied, when per-device memory is on.
    @ObservationIgnored var settingsDeviceUID: String?

    let renderState: TapRenderState
    let meter: LevelMeter

    init(app: ResolvedApp, setting: AppVolumeSetting) {
        id = app.id
        name = app.name
        icon = AppResolver.icon(for: app)
        isRegularApp = app.isRegularApp
        volume = setting.volume
        isMuted = setting.isMuted
        equalizer = setting.equalizer
        routedDeviceUID = setting.outputDeviceUID
        renderState = TapRenderState(gain: setting.isMuted ? 0 : setting.volume)
        renderState.setEqualizer(setting.equalizer)
        meter = LevelMeter(state: renderState)
    }

    var setting: AppVolumeSetting {
        AppVolumeSetting(volume: volume, isMuted: isMuted, equalizer: equalizer, outputDeviceUID: routedDeviceUID)
    }

    var hasEqualizer: Bool {
        !Equalizer.isFlat(equalizer)
    }

    var hasPlayed: Bool {
        isPlaying || stoppedPlayingAt != nil
    }

    func apply(_ setting: AppVolumeSetting) {
        volume = min(TapRenderState.maxGain, max(0, setting.volume))
        isMuted = setting.isMuted
        renderState.setTargetGain(isMuted ? 0 : volume)
        if setting.equalizer != equalizer {
            equalizer = setting.equalizer
            renderState.setEqualizer(equalizer)
        }
        routedDeviceUID = setting.outputDeviceUID
    }

    func setPlaying(_ playing: Bool, at date: Date) {
        guard playing != isPlaying else { return }
        if !playing {
            stoppedPlayingAt = date
        }
        isPlaying = playing
    }

    /// Whether the app should currently be tapped: while playing, and for a grace period afterwards so a
    /// short pause doesn't tear the tap down and rebuild it.
    func needsTap(at date: Date, grace: TimeInterval) -> Bool {
        if isPlaying {
            return true
        }
        guard let stoppedPlayingAt else { return false }
        return date.timeIntervalSince(stoppedPlayingAt) < grace
    }
}
