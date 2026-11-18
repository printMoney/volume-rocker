import Foundation
import Testing
@testable import VolumeRocker

struct ScrollVolumeTests {
    @Test func physicalScrollUpMakesItLouder() {
        // Mouse wheel, natural scrolling off: wheel up gives positive delta.
        #expect(StatusItemController.volumeDelta(scrollingDeltaY: 1, isPrecise: false, isInverted: false) > 0)
        // Natural scrolling on: the same physical motion arrives inverted.
        #expect(StatusItemController.volumeDelta(scrollingDeltaY: -1, isPrecise: false, isInverted: true) > 0)
        #expect(StatusItemController.volumeDelta(scrollingDeltaY: -1, isPrecise: false, isInverted: false) < 0)
    }

    @Test func trackpadStepsAreFinerThanWheelSteps() {
        let wheel = StatusItemController.volumeDelta(scrollingDeltaY: 1, isPrecise: false, isInverted: false)
        let trackpad = StatusItemController.volumeDelta(scrollingDeltaY: 1, isPrecise: true, isInverted: false)
        #expect(trackpad < wheel)
    }

    @Test func hugeFlicksAreCapped() {
        #expect(StatusItemController.volumeDelta(scrollingDeltaY: 500, isPrecise: true, isInverted: false) == 0.25)
    }
}

struct UpdateConfigurationTests {
    private let realKey = "pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="

    @Test func requiresHTTPSFeedAndRealKey() {
        #expect(UpdateController.isConfigured(info: [
            "SUFeedURL": "https://printmoney.github.io/volume-rocker/appcast.xml",
            "SUPublicEDKey": realKey,
        ]))
        #expect(!UpdateController.isConfigured(info: [
            "SUFeedURL": "https://printmoney.github.io/volume-rocker/appcast.xml",
            "SUPublicEDKey": "",
        ]))
        #expect(!UpdateController.isConfigured(info: ["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": realKey]))
        #expect(!UpdateController.isConfigured(info: [:]))
    }

    @Test func shippedInfoPlistHasFeedURL() throws {
        let info = try #require(Bundle(identifier: "io.github.printmoney.VolumeRocker")?.infoDictionary ?? Bundle.main.infoDictionary)
        #expect((info["SUFeedURL"] as? String)?.hasPrefix("https://") == true)
    }
}

@MainActor
struct AppLibraryTests {
    private func makeDefaults() -> UserDefaults {
        let name = "VolumeRockerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func newAppDefaultAppliesToUnadjustedApps() {
        let store = AppVolumeStore(defaults: makeDefaults())
        store.newAppDefault = AppVolumeSetting(volume: 0.6)
        #expect(store.setting(for: "new.app").volume == 0.6)
        // An app set to exactly the default needs no entry, but one at 100% now does.
        store.set(AppVolumeSetting(volume: 0.6), for: "a")
        store.set(AppVolumeSetting(volume: 1), for: "b")
        #expect(!store.hasSetting(for: "a"))
        #expect(store.hasSetting(for: "b"))
    }

    @Test func settingVolumeOfAppThatIsNotRunningIsRemembered() {
        let model = MixerModel(defaults: makeDefaults())
        model.setVolume(0.3, forAppID: "com.example.player")
        model.setMuted(true, forAppID: "com.example.player")
        #expect(model.store.setting(for: "com.example.player") == AppVolumeSetting(volume: 0.3, isMuted: true))
        #expect(model.knownAppIDs.contains("com.example.player"))
        model.setMuted(nil, forAppID: "com.example.player") // toggle
        #expect(model.store.setting(for: "com.example.player").isMuted == false)
    }

    @Test func shortcutVolumeIsClampedWithoutBoost() {
        let model = MixerModel(defaults: makeDefaults())
        model.setVolume(1.8, forAppID: "com.example.player")
        #expect(model.store.setting(for: "com.example.player").volume == 1)
        model.allowBoost = true
        model.setVolume(1.8, forAppID: "com.example.player")
        #expect(model.store.setting(for: "com.example.player").volume == 1.8)
    }

    @Test func exclusionsArePersisted() {
        let defaults = makeDefaults()
        let model = MixerModel(defaults: defaults)
        model.exclude(appID: "com.example.daw")
        #expect(MixerModel(defaults: defaults).excludedAppIDs == ["com.example.daw"])
        model.include(appID: "com.example.daw")
        #expect(MixerModel(defaults: defaults).excludedAppIDs.isEmpty)
    }
}

struct PanelToggleTests {
    @Test func iconClickRightAfterOutsideCloseDoesNotReopen() {
        let now = ContinuousClock.now
        #expect(MixerPanelController.wasJustClosed(at: now - .milliseconds(50), now: now))
        #expect(!MixerPanelController.wasJustClosed(at: now - .seconds(2), now: now))
        #expect(!MixerPanelController.wasJustClosed(at: nil, now: now))
    }
}
