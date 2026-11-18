import AppKit
import CoreAudio

/// Profiles, actions by app ID (used by Shortcuts and Siri), excluded apps and the new-app default.
extension MixerModel {
    // MARK: Profiles

    var activeProfile: MixProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// Saves every app's current settings (running apps and remembered ones) as a profile.
    func saveProfile(named name: String, includeOutputDevice: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var appSettings = store.allGeneralSettings
        for item in apps {
            appSettings[item.id] = item.setting
        }
        let profile = profileStore.save(MixProfile(
            name: trimmed,
            apps: appSettings,
            outputDeviceUID: includeOutputDevice ? output.deviceUID : nil,
            outputDeviceName: includeOutputDevice ? output.deviceName : nil
        ))
        profileStore.setActive(profile.id)
        syncProfiles()
    }

    /// Applies a profile: apps it knows get its settings; apps it doesn't know go back to 100%.
    func applyProfile(_ profile: MixProfile) {
        for item in apps {
            let setting = profile.apps[item.id] ?? .default
            update(item) { $0 = setting }
        }
        for (appID, setting) in profile.apps where itemsByID[appID] == nil {
            store.set(setting, for: appID)
        }
        if let uid = profile.outputDeviceUID, let device = devices.outputs.first(where: { $0.uid == uid }) {
            select(device, for: .output)
        }
        if profileStore.profiles.contains(where: { $0.id == profile.id }) {
            profileStore.setActive(profile.id)
        }
        syncProfiles()
    }

    /// Applies the profile after the active one (wrapping around), for a "next profile" shortcut.
    func applyNextProfile() {
        guard !profiles.isEmpty else { return }
        let index = profiles.firstIndex { $0.id == activeProfileID }.map { ($0 + 1) % profiles.count } ?? 0
        applyProfile(profiles[index])
    }

    func renameProfile(_ profile: MixProfile, to name: String) {
        profileStore.rename(profile.id, to: name)
        syncProfiles()
    }

    func deleteProfile(_ profile: MixProfile) {
        profileStore.delete(profile.id)
        syncProfiles()
    }

    func moveProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        profileStore.move(fromOffsets: source, toOffset: destination)
        syncProfiles()
    }

    func syncProfiles() {
        let changed = profiles.map(\.id) != profileStore.profiles.map(\.id)
        profiles = profileStore.profiles
        activeProfileID = profileStore.activeProfileID
        if changed {
            onProfilesChanged?()
        }
    }

    // MARK: Actions by app ID (Shortcuts, Siri)

    /// Sets an app's volume by bundle ID. If the app isn't running, the volume applies when it next plays.
    func setVolume(_ volume: Float, forAppID appID: String) {
        if let item = itemsByID[appID] {
            setVolume(volume, for: item)
        } else {
            var setting = store.setting(for: appID)
            setting.volume = min(maxAppVolume, max(0, volume))
            if setting.volume > 0 {
                setting.isMuted = false
            }
            store.set(setting, for: appID)
        }
    }

    /// Mutes (true), unmutes (false) or toggles (nil) an app by bundle ID.
    func setMuted(_ muted: Bool?, forAppID appID: String) {
        if let item = itemsByID[appID] {
            update(item) { $0.isMuted = muted ?? !$0.isMuted }
        } else {
            var setting = store.setting(for: appID)
            setting.isMuted = muted ?? !setting.isMuted
            store.set(setting, for: appID)
        }
    }

    /// Apps worth offering in Shortcuts: running ones and ones with saved settings.
    var knownAppIDs: [String] {
        Array(Set(apps.map(\.id)).union(store.allGeneralSettings.keys)).sorted()
    }

    func appName(forID appID: String) -> String {
        if let item = itemsByID[appID] {
            return item.name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        return appID
    }

    // MARK: Excluded apps and defaults

    func exclude(appID: String) {
        excludedAppIDs.insert(appID)
        persistExclusions()
        if let item = itemsByID.removeValue(forKey: appID) {
            apps.removeAll { $0 === item }
        }
        requestEngineSync()
    }

    func include(appID: String) {
        excludedAppIDs.remove(appID)
        persistExclusions()
        monitor.refresh()
    }

    private func persistExclusions() {
        defaults.set(excludedAppIDs.sorted(), forKey: Keys.excludedApps)
    }

    func applyNewAppDefault() {
        store.newAppDefault = AppVolumeSetting(volume: newAppVolume)
        for item in apps where !store.hasSetting(for: item.id) && item.settingsDeviceUID == nil {
            item.apply(store.newAppDefault)
        }
    }
}
