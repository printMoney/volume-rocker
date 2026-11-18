import Foundation

/// An app's saved volume, mute, equalizer and output routing.
struct AppVolumeSetting: Codable, Equatable, Sendable {
    /// 0...2 (100% = unchanged, up to 200% with boost).
    var volume: Float = 1
    var isMuted = false
    /// Ten band gains in dB, or nil for flat.
    var equalizer: [Float]?
    /// UID of the device this app is routed to, or nil to play where the app itself chooses.
    var outputDeviceUID: String?

    static let `default` = AppVolumeSetting()

    init(volume: Float = 1, isMuted: Bool = false, equalizer: [Float]? = nil, outputDeviceUID: String? = nil) {
        self.volume = volume
        self.isMuted = isMuted
        self.equalizer = Equalizer.isFlat(equalizer) ? nil : equalizer
        self.outputDeviceUID = outputDeviceUID
    }

    /// Tolerant decoding: settings saved by older versions (without EQ or routing) still load.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        let gains = try container.decodeIfPresent([Float].self, forKey: .equalizer)
        equalizer = gains?.count == Equalizer.bandCount && !Equalizer.isFlat(gains) ? gains : nil
        outputDeviceUID = try container.decodeIfPresent(String.self, forKey: .outputDeviceUID)
    }
}

/// Remembers each app's volume and mute by bundle ID, across restarts and reboots.
/// Writes are batched, so dragging a slider doesn't hit the disk dozens of times per second.
@MainActor
final class AppVolumeStore {
    static let storageKey = "appVolumeSettings"

    private let defaults: UserDefaults
    private var settings: [String: AppVolumeSetting]
    /// Setting for apps that have never been adjusted (Settings → Apps → default volume).
    var newAppDefault = AppVolumeSetting.default
    private var saveScheduled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: AppVolumeSetting].self, from: data) {
            settings = decoded
        } else {
            settings = [:]
        }
    }

    /// The saved setting for an app. With a `deviceUID` (per-device memory turned on), the device-specific
    /// setting wins; if there is none yet, the app's general setting is used as the starting point.
    ///
    /// Output routing is never per device: it always comes from the app's general setting. (Otherwise routing
    /// an app to another device would load that device's settings, which would route it somewhere else.)
    func setting(for appID: String, deviceUID: String? = nil) -> AppVolumeSetting {
        let general = settings[appID] ?? newAppDefault
        if let deviceUID, var deviceSetting = settings[Self.key(appID: appID, deviceUID: deviceUID)] {
            deviceSetting.outputDeviceUID = general.outputDeviceUID
            return deviceSetting
        }
        return general
    }

    /// Whether the app has a saved general setting (as opposed to using the new-app default).
    func hasSetting(for appID: String) -> Bool {
        settings[appID] != nil
    }

    func set(_ setting: AppVolumeSetting, for appID: String, deviceUID: String? = nil) {
        if let deviceUID {
            // Stored even when it equals the default, because it must override the app's general setting.
            var deviceSetting = setting
            deviceSetting.outputDeviceUID = nil
            settings[Self.key(appID: appID, deviceUID: deviceUID)] = deviceSetting
            var general = settings[appID] ?? newAppDefault
            general.outputDeviceUID = setting.outputDeviceUID
            settings[appID] = general == newAppDefault ? nil : general
        } else {
            // Apps left at the default don't need an entry.
            settings[appID] = setting == newAppDefault ? nil : setting
        }
        scheduleSave()
    }

    /// Key for a device-specific setting. "|" keeps keys readable in the preferences file.
    nonisolated static func key(appID: String, deviceUID: String) -> String {
        "\(deviceUID)|\(appID)"
    }

    /// General settings of every app that has any, for saving a profile.
    var allGeneralSettings: [String: AppVolumeSetting] {
        settings.filter { !$0.key.contains("|") }
    }

    /// Writes pending changes immediately (also called when the app quits).
    func flush() {
        saveScheduled = false
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, saveScheduled else { return }
            flush()
        }
    }
}
