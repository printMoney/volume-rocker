import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// The system's default output (or input) device and its volume and mute.
/// Stays in sync with the keyboard volume keys and Control Center through Core Audio listeners.
///
/// Changing an input device's volume does not record audio, so it needs no microphone permission.
@MainActor
@Observable
final class DefaultDeviceController {
    let direction: AudioDirection
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

    private let volumeAddress: AudioObjectPropertyAddress
    private let muteAddress: AudioObjectPropertyAddress

    init(direction: AudioDirection) {
        self.direction = direction
        volumeAddress = AudioObjectPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: direction.scope)
        muteAddress = AudioObjectPropertyAddress(kAudioDevicePropertyMute, scope: direction.scope)
    }

    var isAvailable: Bool {
        deviceID.isValid
    }

    func start() {
        defaultDeviceListener = PropertyListener(
            objectID: .system,
            address: AudioObjectPropertyAddress(direction.defaultDeviceSelector)
        ) { [weak self] in self?.reloadDevice() }
        reloadDevice()
    }

    /// Re-reads everything from scratch, e.g. after the audio system restarted and all IDs changed.
    func restart() {
        deviceListeners = []
        deviceID = .unknown
        start()
    }

    func setVolume(_ newValue: Float) {
        let newValue = min(1, max(0, newValue))
        guard hasVolumeControl else { return }
        do {
            try deviceID.write(volumeAddress, value: Float32(newValue))
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
            try deviceID.write(muteAddress, value: UInt32(muted ? 1 : 0))
            isMuted = muted
        } catch {
            Log.devices.error("Set mute failed: \(String(describing: error), privacy: .public)")
        }
    }

    #if DEBUG
        /// Fills in example values for rendering screenshots (Scripts/render-readme-images.sh).
        func setPreview(deviceName: String, volume: Float) {
            self.deviceName = deviceName
            self.volume = volume
            deviceID = 1
            hasVolumeControl = true
            hasMuteControl = true
        }
    #endif

    private func reloadDevice() {
        let newID = (try? AudioObjectID.system.read(
            AudioObjectPropertyAddress(direction.defaultDeviceSelector), default: AudioDeviceID.unknown
        )) ?? .unknown
        let changed = newID != deviceID
        deviceID = newID
        deviceUID = newID.isValid ? ((try? newID.deviceUID()) ?? "") : ""
        deviceName = newID.isValid ? newID.objectName : ""

        if changed {
            deviceListeners = [volumeAddress, muteAddress].compactMap { address in
                PropertyListener(objectID: newID, address: address) { [weak self] in self?.refreshVolume() }
            }
            let kind = direction == .output ? "output" : "input"
            Log.devices.info("Default \(kind, privacy: .public) device: \(self.deviceName, privacy: .public)")
        }
        refreshVolume()
        if changed {
            onDeviceChange?()
        }
    }

    private func refreshVolume() {
        hasVolumeControl = deviceID.isSettable(volumeAddress)
        hasMuteControl = deviceID.isSettable(muteAddress)
        volume = (try? deviceID.read(volumeAddress, default: Float32(1))) ?? 1
        isMuted = ((try? deviceID.read(muteAddress, default: UInt32(0))) ?? 0) != 0
    }
}
