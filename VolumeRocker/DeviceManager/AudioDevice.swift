import CoreAudio
import Foundation

/// Output or input.
enum AudioDirection: Sendable {
    case output
    case input

    var scope: AudioObjectPropertyScope {
        switch self {
        case .output: kAudioObjectPropertyScopeOutput
        case .input: kAudioObjectPropertyScopeInput
        }
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        case .input: kAudioHardwarePropertyDefaultInputDevice
        }
    }
}

/// How a device is connected, used to pick its icon.
enum DeviceTransport: Equatable, Sendable {
    case builtIn, bluetooth, usb, hdmi, displayPort, airPlay, thunderbolt, continuity, virtual, aggregate, other

    init(coreAudioValue: UInt32) {
        switch coreAudioValue {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeHDMI: self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: self = .continuity
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: self = .aggregate
        default: self = .other
        }
    }
}

/// An audio device the user can pick.
struct AudioDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: DeviceTransport
    let hasOutput: Bool
    let hasInput: Bool

    /// SF Symbol for this device, like the icons in Control Center's Sound menu.
    func symbolName(for direction: AudioDirection) -> String {
        DeviceSymbol.name(transport: transport, direction: direction, deviceName: name)
    }
}

enum DeviceSymbol {
    static func name(transport: DeviceTransport, direction: AudioDirection, deviceName: String) -> String {
        let lowercased = deviceName.lowercased()
        switch transport {
        case .bluetooth:
            if lowercased.contains("airpods max") {
                return "airpods.max"
            }
            if lowercased.contains("airpods pro") {
                return "airpods.pro"
            }
            if lowercased.contains("airpods") {
                return "airpods"
            }
            if lowercased.contains("beats") {
                return "beats.headphones"
            }
            if lowercased.contains("speaker") || lowercased.contains("boom") {
                return "hifispeaker.fill"
            }
            return direction == .input ? "headset" : "headphones"
        case .builtIn:
            if direction == .input {
                return "mic.fill"
            }
            return lowercased.contains("headphone") ? "headphones" : "speaker.wave.2.fill"
        case .usb, .thunderbolt:
            return direction == .input ? "mic.fill" : "cable.connector"
        case .hdmi:
            return "tv"
        case .displayPort:
            return "display"
        case .airPlay:
            return "airplay.audio"
        case .continuity:
            return "iphone"
        case .virtual, .aggregate, .other:
            return direction == .input ? "mic.fill" : "waveform"
        }
    }
}

extension AudioDevice {
    /// Reads a device's details, or nil if it isn't one a user should pick.
    static func read(_ id: AudioDeviceID) -> AudioDevice? {
        guard let uid = try? id.deviceUID(), !uid.isEmpty,
              !uid.hasPrefix(AudioEngine.aggregateUIDPrefix),
              !uid.hasPrefix("CADefaultDeviceAggregate")
        else { return nil }
        let isHidden = (try? id.read(AudioObjectPropertyAddress(kAudioDevicePropertyIsHidden), default: UInt32(0))) ?? 0
        guard isHidden == 0 else { return nil }

        let transport = (try? id.read(AudioObjectPropertyAddress(kAudioDevicePropertyTransportType), default: UInt32(0))) ?? 0
        return AudioDevice(
            id: id,
            uid: uid,
            name: id.objectName,
            transport: DeviceTransport(coreAudioValue: transport),
            hasOutput: id.canBeDefault(for: .output),
            hasInput: id.canBeDefault(for: .input)
        )
    }
}

extension AudioObjectID {
    func canBeDefault(for direction: AudioDirection) -> Bool {
        guard streamCount(scope: direction.scope) > 0 else { return false }
        let address = AudioObjectPropertyAddress(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: direction.scope)
        return ((try? read(address, default: UInt32(1))) ?? 1) != 0
    }

    func nominalSampleRate() -> Double {
        (try? read(AudioObjectPropertyAddress(kAudioDevicePropertyNominalSampleRate), default: Float64(0))) ?? 0
    }
}
