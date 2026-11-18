import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// The system's default output device and its master volume and mute.
/// Stays in sync with the keyboard volume keys and Control Center through Core Audio listeners.
@MainActor
@Observable
final class OutputDeviceController {
    private(set) var deviceID = AudioObjectID.unknown
    private(set) var deviceUID = ""
    private(set) var deviceName = ""
    private(set) var volume: Float = 1
    private(set) var isMuted = false
    private(set) var hasVolumeControl = false
    private(set) var hasMuteControl = false

    @ObservationIgnored var onDeviceChange: (@MainActor () -> Void)?
    @ObservationIgnored private var defaultDeviceListener: PropertyListener?
    @ObservationIgnored private var deviceListeners: [PropertyListener] = []

    private static let volumeAddress = AudioObjectPropertyAddress(
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput
    )
    private static let muteAddress = AudioObjectPropertyAddress(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)

    func start() {
        defaultDeviceListener = PropertyListener(
            objectID: .system,
            address: AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        ) { [weak self] in self?.reloadDevice() }
        reloadDevice()
    }

    func setVolume(_ newValue: Float) {
        let newValue = min(1, max(0, newValue))
        guard hasVolumeControl else { return }
        do {
            try deviceID.write(Self.volumeAddress, value: Float32(newValue))
            volume = newValue
            if isMuted, newValue > 0 {
                setMuted(false)
            }
        } catch {
            Log.devices.error("Set volume failed: \(String(describing: error), privacy: .public)")
        }
    }

    func setMuted(_ muted: Bool) {
        guard hasMuteControl else { return }
        do {
            try deviceID.write(Self.muteAddress, value: UInt32(muted ? 1 : 0))
            isMuted = muted
        } catch {
            Log.devices.error("Set mute failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func reloadDevice() {
        let newID = (try? AudioObjectID.defaultOutputDevice()) ?? .unknown
        let changed = newID != deviceID
        deviceID = newID
        deviceUID = (try? newID.deviceUID()) ?? ""
        deviceName = newID.objectName

        if changed {
            deviceListeners = [Self.volumeAddress, Self.muteAddress].compactMap { address in
                PropertyListener(objectID: newID, address: address) { [weak self] in self?.refreshVolume() }
            }
            Log.devices.info("Output device: \(self.deviceName, privacy: .public)")
        }
        refreshVolume()
        if changed {
            onDeviceChange?()
        }
    }

    private func refreshVolume() {
        hasVolumeControl = deviceID.isSettable(Self.volumeAddress)
        hasMuteControl = deviceID.isSettable(Self.muteAddress)
        volume = (try? deviceID.read(Self.volumeAddress, default: Float32(1))) ?? 1
        isMuted = ((try? deviceID.read(Self.muteAddress, default: UInt32(0))) ?? 0) != 0
    }
}
