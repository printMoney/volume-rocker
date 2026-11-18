import Foundation
import Testing
@testable import VolumeRocker

@MainActor
private func makeDefaults() -> UserDefaults {
    let name = "VolumeRockerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

struct AppVolumeSettingTests {
    @Test func loadsSettingsSavedByOlderVersions() throws {
        let old = Data(#"{"volume":0.4,"isMuted":true}"#.utf8)
        let setting = try JSONDecoder().decode(AppVolumeSetting.self, from: old)
        #expect(setting == AppVolumeSetting(volume: 0.4, isMuted: true))
        #expect(setting.equalizer == nil)
        #expect(setting.outputDeviceUID == nil)
    }

    @Test func roundTripsAllFields() throws {
        let setting = AppVolumeSetting(
            volume: 1.5, isMuted: false, equalizer: Equalizer.presets[1].gains, outputDeviceUID: "speakers"
        )
        let decoded = try JSONDecoder().decode(AppVolumeSetting.self, from: JSONEncoder().encode(setting))
        #expect(decoded == setting)
    }

    @Test func flatOrMalformedEqualizerIsStoredAsNil() throws {
        #expect(AppVolumeSetting(equalizer: Equalizer.flat).equalizer == nil)
        let malformed = Data(#"{"volume":1,"isMuted":false,"equalizer":[1,2,3]}"#.utf8)
        #expect(try JSONDecoder().decode(AppVolumeSetting.self, from: malformed).equalizer == nil)
    }
}

@MainActor
struct RoutingStoreTests {
    @Test func routingIsSharedAcrossDevices() {
        let store = AppVolumeStore(defaults: makeDefaults())
        store.set(AppVolumeSetting(volume: 0.5, outputDeviceUID: "speakers"), for: "app", deviceUID: "headphones")
        // Routing is visible from any device scope and the general one, but the volume stays per device.
        #expect(store.setting(for: "app", deviceUID: "headphones").outputDeviceUID == "speakers")
        #expect(store.setting(for: "app", deviceUID: "headphones").volume == 0.5)
        #expect(store.setting(for: "app").outputDeviceUID == "speakers")
        #expect(store.setting(for: "app").volume == 1)
    }
}

@MainActor
struct ProfileStoreTests {
    @Test func savesAndReloadsProfiles() {
        let defaults = makeDefaults()
        let store = ProfileStore(defaults: defaults)
        let saved = store.save(MixProfile(name: " Work ", apps: ["a": AppVolumeSetting(volume: 0.3)]))
        store.setActive(saved.id)

        let reloaded = ProfileStore(defaults: defaults)
        #expect(reloaded.profiles.map(\.name) == ["Work"])
        #expect(reloaded.activeProfileID == saved.id)
    }

    @Test func savingWithSameNameReplaces() {
        let store = ProfileStore(defaults: makeDefaults())
        let first = store.save(MixProfile(name: "Gaming", apps: [:]))
        let second = store.save(MixProfile(name: "gaming", apps: ["b": .default]))
        #expect(store.profiles.count == 1)
        #expect(first.id == second.id)
        #expect(store.profiles.first?.apps.keys.contains("b") == true)
    }

    @Test func deletingActiveProfileClearsActive() {
        let store = ProfileStore(defaults: makeDefaults())
        let profile = store.save(MixProfile(name: "Movie", apps: [:]))
        store.setActive(profile.id)
        store.delete(profile.id)
        #expect(store.profiles.isEmpty)
        #expect(store.activeProfileID == nil)
    }

    @Test func renameIgnoresBlankNames() {
        let store = ProfileStore(defaults: makeDefaults())
        let profile = store.save(MixProfile(name: "Work", apps: [:]))
        store.rename(profile.id, to: "   ")
        #expect(store.profiles.first?.name == "Work")
        store.rename(profile.id, to: "Office")
        #expect(store.profiles.first?.name == "Office")
    }
}

@MainActor
struct MixerProfileTests {
    @Test func applyingProfileUpdatesRememberedApps() {
        let defaults = makeDefaults()
        let model = MixerModel(defaults: defaults)
        let profile = MixProfile(name: "Quiet", apps: ["com.example.music": AppVolumeSetting(volume: 0.2)])
        model.applyProfile(profile)
        #expect(model.activeProfileID == nil) // not saved through the model, so not in its list

        model.saveProfile(named: "Quiet", includeOutputDevice: false)
        #expect(model.profiles.map(\.name) == ["Quiet"])
        #expect(model.activeProfile?.apps["com.example.music"]?.volume == 0.2)
    }

    @Test func nextProfileCyclesThroughProfiles() {
        let model = MixerModel(defaults: makeDefaults())
        model.saveProfile(named: "One", includeOutputDevice: false)
        model.saveProfile(named: "Two", includeOutputDevice: false)
        #expect(model.activeProfile?.name == "Two")
        model.applyNextProfile()
        #expect(model.activeProfile?.name == "One")
        model.applyNextProfile()
        #expect(model.activeProfile?.name == "Two")
    }

    @Test func turningOffBoostDoesNotLeaveVolumesAbove100() {
        let model = MixerModel(defaults: makeDefaults())
        model.allowBoost = true
        #expect(model.maxAppVolume == 2)
        model.allowBoost = false
        #expect(model.maxAppVolume == 1)
    }
}
