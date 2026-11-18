import Foundation

/// An app's saved volume and mute state.
struct AppVolumeSetting: Codable, Equatable, Sendable {
    var volume: Float = 1
    var isMuted = false

    static let `default` = AppVolumeSetting()
}

/// Remembers each app's volume and mute by bundle ID, across restarts and reboots.
/// Writes are batched, so dragging a slider doesn't hit the disk dozens of times per second.
@MainActor
final class AppVolumeStore {
    static let storageKey = "appVolumeSettings"

    private let defaults: UserDefaults
    private var settings: [String: AppVolumeSetting]
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
    func setting(for appID: String, deviceUID: String? = nil) -> AppVolumeSetting {
        if let deviceUID, let deviceSetting = settings[Self.key(appID: appID, deviceUID: deviceUID)] {
            return deviceSetting
        }
        return settings[appID] ?? .default
    }

    func set(_ setting: AppVolumeSetting, for appID: String, deviceUID: String? = nil) {
        if let deviceUID {
            // Stored even when it equals the default, because it must override the app's general setting.
            settings[Self.key(appID: appID, deviceUID: deviceUID)] = setting
        } else {
            // Apps left at the default don't need an entry.
            settings[appID] = setting == .default ? nil : setting
        }
        scheduleSave()
    }

    /// Key for a device-specific setting. "|" keeps keys readable in the preferences file.
    nonisolated static func key(appID: String, deviceUID: String) -> String {
        "\(deviceUID)|\(appID)"
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
