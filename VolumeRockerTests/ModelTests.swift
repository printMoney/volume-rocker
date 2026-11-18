import CoreAudio
import Foundation
import Testing
@testable import VolumeRocker

struct MeterBallisticsTests {
    @Test func mapsDecibelsToZeroToOne() {
        #expect(MeterBallistics.normalized(peak: 0) == 0)
        #expect(MeterBallistics.normalized(peak: 1) == 1)
        #expect(MeterBallistics.normalized(peak: 2) == 1)
        #expect(abs(MeterBallistics.normalized(peak: 0.001) - 0) < 0.0001) // −60 dB
        #expect(abs(MeterBallistics.normalized(peak: 0.0316) - 0.5) < 0.01) // ≈ −30 dB
    }

    @Test func risesInstantlyAndFallsGradually() {
        var meter = MeterBallistics()
        #expect(meter.update(peak: 1, elapsed: 0) == 1)
        let afterShortTime = meter.update(peak: 0, elapsed: 0.1)
        #expect(afterShortTime < 1)
        #expect(afterShortTime > 0.9)
        #expect(meter.update(peak: 0, elapsed: 5) == 0)
    }
}

struct VolumeSymbolTests {
    @Test func picksSymbolForLevel() {
        #expect(VolumeSymbol.name(volume: 0.5, isMuted: true) == "speaker.slash.fill")
        #expect(VolumeSymbol.name(volume: 0, isMuted: false) == "speaker.slash.fill")
        #expect(VolumeSymbol.name(volume: 0.2, isMuted: false) == "speaker.wave.1.fill")
        #expect(VolumeSymbol.name(volume: 0.5, isMuted: false) == "speaker.wave.2.fill")
        #expect(VolumeSymbol.name(volume: 1, isMuted: false) == "speaker.wave.3.fill")
    }
}

struct AppResolverTests {
    @Test func findsOutermostAppForHelpers() {
        let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/"
            + "Versions/131.0/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        #expect(AppResolver.outermostAppBundlePath(in: chromeHelper) == "/Applications/Google Chrome.app")
    }

    @Test func findsAppForMainExecutable() {
        let spotify = "/Applications/Spotify.app/Contents/MacOS/Spotify"
        #expect(AppResolver.outermostAppBundlePath(in: spotify) == "/Applications/Spotify.app")
    }

    @Test func returnsNilOutsideAppBundles() {
        let webKit = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/"
            + "com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        #expect(AppResolver.outermostAppBundlePath(in: webKit) == nil)
        #expect(AppResolver.outermostAppBundlePath(in: "/usr/sbin/coreaudiod") == nil)
    }
}

@MainActor
struct AppVolumeStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "VolumeRockerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func returnsDefaultForUnknownApps() {
        let store = AppVolumeStore(defaults: makeDefaults())
        #expect(store.setting(for: "com.example.unknown") == .default)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let store = AppVolumeStore(defaults: defaults)
        store.set(AppVolumeSetting(volume: 0.3, isMuted: true), for: "com.spotify.client")
        store.flush()

        let reloaded = AppVolumeStore(defaults: defaults)
        #expect(reloaded.setting(for: "com.spotify.client") == AppVolumeSetting(volume: 0.3, isMuted: true))
    }

    @Test func defaultSettingsAreNotStored() throws {
        let defaults = makeDefaults()
        let store = AppVolumeStore(defaults: defaults)
        store.set(AppVolumeSetting(volume: 0.5, isMuted: false), for: "a")
        store.set(.default, for: "a")
        store.flush()
        let data = try #require(defaults.data(forKey: AppVolumeStore.storageKey))
        let decoded = try JSONDecoder().decode([String: AppVolumeSetting].self, from: data)
        #expect(decoded.isEmpty)
    }

    @Test func ignoresCorruptData() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: AppVolumeStore.storageKey)
        let store = AppVolumeStore(defaults: defaults)
        #expect(store.setting(for: "x") == .default)
    }
}

@MainActor
struct AppAudioItemTests {
    private let app = ResolvedApp(id: "com.example.app", name: "Example", bundlePath: nil, isRegularApp: true)

    @Test func appliesSavedSettingToRenderGain() {
        let item = AppAudioItem(app: app, setting: AppVolumeSetting(volume: 0.4, isMuted: false))
        #expect(item.renderState.targetGain == 0.4)
        item.apply(AppVolumeSetting(volume: 0.4, isMuted: true))
        #expect(item.renderState.targetGain == 0)
        item.apply(AppVolumeSetting(volume: 1.5, isMuted: false))
        #expect(item.renderState.targetGain == 1.5)
        item.apply(AppVolumeSetting(volume: 3, isMuted: false))
        #expect(item.volume == 2)
        #expect(item.renderState.targetGain == 2)
    }

    @Test func keepsTapDuringGracePeriodAfterPlaying() {
        let item = AppAudioItem(app: app, setting: .default)
        let start = Date()
        #expect(!item.needsTap(at: start, grace: 30))
        item.setPlaying(true, at: start)
        #expect(item.needsTap(at: start, grace: 30))
        item.setPlaying(false, at: start)
        #expect(item.needsTap(at: start.addingTimeInterval(10), grace: 30))
        #expect(!item.needsTap(at: start.addingTimeInterval(31), grace: 30))
        #expect(item.hasPlayed)
    }
}

struct CoreAudioSupportTests {
    @Test func formatsFourCharacterCodes() {
        #expect(OSStatus(bitPattern: 0x7768_6F3F).fourCharCode == "who?")
        #expect(OSStatus(-50).fourCharCode == "-50")
    }

    @Test func tapRequestsCompareRenderStateByIdentity() {
        let state = TapRenderState()
        let request = TapRequest(key: "a", processObjectIDs: [1], outputDeviceID: 2, outputDeviceUID: "u", renderState: state)
        let same = TapRequest(key: "a", processObjectIDs: [1], outputDeviceID: 2, outputDeviceUID: "u", renderState: state)
        let other = TapRequest(key: "a", processObjectIDs: [1], outputDeviceID: 2, outputDeviceUID: "u", renderState: TapRenderState())
        #expect(request == same)
        #expect(request != other)
    }
}
