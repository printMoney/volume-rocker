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

    func setting(for appID: String) -> AppVolumeSetting {
        settings[appID] ?? .default
    }

    func set(_ setting: AppVolumeSetting, for appID: String) {
        // Apps left at the default don't need an entry.
        settings[appID] = setting == .default ? nil : setting
        scheduleSave()
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
