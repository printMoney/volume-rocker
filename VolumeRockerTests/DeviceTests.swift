import CoreAudio
import Foundation
import Testing
@testable import VolumeRocker

struct DeviceTransportTests {
    @Test func mapsCoreAudioTransportTypes() {
        #expect(DeviceTransport(coreAudioValue: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(DeviceTransport(coreAudioValue: kAudioDeviceTransportTypeBluetooth) == .bluetooth)
        #expect(DeviceTransport(coreAudioValue: kAudioDeviceTransportTypeBluetoothLE) == .bluetooth)
        #expect(DeviceTransport(coreAudioValue: kAudioDeviceTransportTypeHDMI) == .hdmi)
        #expect(DeviceTransport(coreAudioValue: kAudioDeviceTransportTypeAirPlay) == .airPlay)
        #expect(DeviceTransport(coreAudioValue: kAudioDeviceTransportTypeUSB) == .usb)
        #expect(DeviceTransport(coreAudioValue: 0) == .other)
    }
}

struct DeviceSymbolTests {
    @Test func picksHeadphoneSymbolsByName() {
        #expect(DeviceSymbol.name(transport: .bluetooth, direction: .output, deviceName: "Anna’s AirPods Pro") == "airpods.pro")
        #expect(DeviceSymbol.name(transport: .bluetooth, direction: .output, deviceName: "AirPods Max") == "airpods.max")
        #expect(DeviceSymbol.name(transport: .bluetooth, direction: .output, deviceName: "AirPods") == "airpods")
        #expect(DeviceSymbol.name(transport: .bluetooth, direction: .output, deviceName: "WH-1000XM5") == "headphones")
        #expect(DeviceSymbol.name(transport: .bluetooth, direction: .input, deviceName: "WH-1000XM5") == "headset")
    }

    @Test func picksSymbolsByTransport() {
        #expect(DeviceSymbol.name(transport: .builtIn, direction: .output, deviceName: "MacBook Air Speakers") == "speaker.wave.2.fill")
        #expect(DeviceSymbol.name(transport: .builtIn, direction: .input, deviceName: "MacBook Air Microphone") == "mic.fill")
        #expect(DeviceSymbol.name(transport: .hdmi, direction: .output, deviceName: "LG TV") == "tv")
        #expect(DeviceSymbol.name(transport: .displayPort, direction: .output, deviceName: "Studio Display") == "display")
        #expect(DeviceSymbol.name(transport: .airPlay, direction: .output, deviceName: "Living Room") == "airplay.audio")
    }
}

struct DeviceListTests {
    private func device(_ id: AudioDeviceID, _ name: String, _ transport: DeviceTransport) -> AudioDevice {
        AudioDevice(id: id, uid: "uid-\(id)", name: name, transport: transport, hasOutput: true, hasInput: false)
    }

    @Test func sortsBuiltInFirstThenAlphabetically() {
        let sorted = AudioDeviceList.sorted([
            device(1, "Zebra USB", .usb),
            device(2, "AirPods", .bluetooth),
            device(3, "MacBook Speakers", .builtIn),
            device(4, "airplay room", .airPlay),
        ])
        #expect(sorted.map(\.name) == ["MacBook Speakers", "airplay room", "AirPods", "Zebra USB"])
    }
}

@MainActor
struct PerDeviceStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "VolumeRockerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func fallsBackToGeneralSettingForNewDevice() {
        let store = AppVolumeStore(defaults: makeDefaults())
        store.set(AppVolumeSetting(volume: 0.6, isMuted: false), for: "app")
        #expect(store.setting(for: "app", deviceUID: "headphones").volume == 0.6)
    }

    @Test func keepsSeparateVolumesPerDevice() {
        let defaults = makeDefaults()
        let store = AppVolumeStore(defaults: defaults)
        store.set(AppVolumeSetting(volume: 0.2, isMuted: false), for: "app", deviceUID: "speakers")
        store.set(AppVolumeSetting(volume: 0.9, isMuted: false), for: "app", deviceUID: "headphones")
        store.flush()

        let reloaded = AppVolumeStore(defaults: defaults)
        #expect(reloaded.setting(for: "app", deviceUID: "speakers").volume == 0.2)
        #expect(reloaded.setting(for: "app", deviceUID: "headphones").volume == 0.9)
        #expect(reloaded.setting(for: "app") == .default)
    }

    @Test func deviceSettingAtDefaultStillOverridesGeneralSetting() {
        let store = AppVolumeStore(defaults: makeDefaults())
        store.set(AppVolumeSetting(volume: 0.3, isMuted: false), for: "app")
        store.set(.default, for: "app", deviceUID: "speakers")
        #expect(store.setting(for: "app", deviceUID: "speakers") == .default)
    }
}

struct TapRequestGenerationTests {
    @Test func differentGenerationForcesRebuild() {
        let state = TapRenderState()
        let first = TapRequest(key: "a", processObjectIDs: [1], outputDeviceID: 2, outputDeviceUID: "u", renderState: state)
        var second = first
        second.generation += 1
        #expect(first != second)
    }
}

struct AggregateDescriptionTests {
    private let description = TapSession.aggregateDescription(
        name: "Test", outputDeviceUID: "speaker-uid", tapUUID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )

    /// Regression test: without maximum quality, 48 kHz taps on 44.1 kHz Bluetooth headphones sounded distorted.
    @Test func requestsBestRateConversionQualityForTap() throws {
        let taps = try #require(description[kAudioAggregateDeviceTapListKey] as? [[String: Any]])
        let tap = try #require(taps.first)
        #expect(tap[kAudioSubTapDriftCompensationKey] as? Bool == true)
        #expect(tap[kAudioSubTapDriftCompensationQualityKey] as? UInt32 == kAudioAggregateDriftCompensationMaxQuality)
        #expect(tap[kAudioSubTapUIDKey] as? String == "00000000-0000-0000-0000-000000000001")
    }

    @Test func isPrivateAndUsesOutputDeviceAsMain() {
        #expect(description[kAudioAggregateDeviceIsPrivateKey] as? Bool == true)
        #expect(description[kAudioAggregateDeviceMainSubDeviceKey] as? String == "speaker-uid")
        #expect((description[kAudioAggregateDeviceUIDKey] as? String)?.hasPrefix(AudioEngine.aggregateUIDPrefix) == true)
    }
}
