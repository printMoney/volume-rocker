import CoreAudio
import Foundation
import Observation

/// Every output and input device the user can pick, kept up to date as devices connect and disconnect.
@MainActor
@Observable
final class AudioDeviceList {
    private(set) var outputs: [AudioDevice] = []
    private(set) var inputs: [AudioDevice] = []

    /// Called when devices appear or disappear.
    @ObservationIgnored var onDevicesChanged: (@MainActor () -> Void)?
    /// Called with a device's UID when its sample rate changes.
    @ObservationIgnored var onSampleRateChanged: (@MainActor (String) -> Void)?

    @ObservationIgnored private var listListener: PropertyListener?
    @ObservationIgnored private var rateListeners: [AudioDeviceID: PropertyListener] = [:]
    @ObservationIgnored private var sampleRates: [AudioDeviceID: Double] = [:]

    func start() {
        listListener = PropertyListener(
            objectID: .system,
            address: AudioObjectPropertyAddress(kAudioHardwarePropertyDevices)
        ) { [weak self] in self?.reload(notify: true) }
        reload(notify: false)
    }

    func stop() {
        listListener = nil
        rateListeners.removeAll()
    }

    func device(withID id: AudioDeviceID) -> AudioDevice? {
        outputs.first { $0.id == id } ?? inputs.first { $0.id == id }
    }

    func reload(notify: Bool) {
        let ids = (try? AudioObjectID.system.readArray(
            AudioObjectPropertyAddress(kAudioHardwarePropertyDevices), of: AudioDeviceID.self
        )) ?? []
        let devices = ids.compactMap(AudioDevice.read)

        let newOutputs = Self.sorted(devices.filter(\.hasOutput))
        let newInputs = Self.sorted(devices.filter(\.hasInput))
        if newOutputs != outputs {
            outputs = newOutputs
            Log.devices.info("Outputs: \(newOutputs.map { "\($0.name) [\($0.transport)]" }, privacy: .public)")
        }
        if newInputs != inputs {
            inputs = newInputs
            Log.devices.info("Inputs: \(newInputs.map(\.name), privacy: .public)")
        }

        // Watch sample rates of output devices, so taps can be rebuilt when the format changes.
        let outputIDs = Set(newOutputs.map(\.id))
        rateListeners = rateListeners.filter { outputIDs.contains($0.key) }
        sampleRates = sampleRates.filter { outputIDs.contains($0.key) }
        for device in newOutputs where rateListeners[device.id] == nil {
            sampleRates[device.id] = device.id.nominalSampleRate()
            rateListeners[device.id] = PropertyListener(
                objectID: device.id,
                address: AudioObjectPropertyAddress(kAudioDevicePropertyNominalSampleRate)
            ) { [weak self] in self?.sampleRateDidChange(device) }
        }

        if notify {
            onDevicesChanged?()
        }
    }

    private func sampleRateDidChange(_ device: AudioDevice) {
        let rate = device.id.nominalSampleRate()
        guard rate != sampleRates[device.id] else { return }
        sampleRates[device.id] = rate
        Log.devices.info("\(device.name, privacy: .public) sample rate is now \(rate) Hz")
        onSampleRateChanged?(device.uid)
    }

    /// Built-in devices first, then alphabetical, like Control Center.
    nonisolated static func sorted(_ devices: [AudioDevice]) -> [AudioDevice] {
        devices.sorted { lhs, rhs in
            if (lhs.transport == .builtIn) != (rhs.transport == .builtIn) {
                return lhs.transport == .builtIn
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: Switching

    /// Makes `device` the system default for `direction`, exactly as choosing it in Control Center does.
    func makeDefault(_ device: AudioDevice, for direction: AudioDirection) {
        let systemOutputAddress = AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice)
        let alertsFollowedDefault = direction == .output
            && (try? AudioObjectID.system.read(systemOutputAddress, default: AudioDeviceID.unknown))
            == (try? AudioObjectID.defaultOutputDevice())
        do {
            try AudioObjectID.system.write(AudioObjectPropertyAddress(direction.defaultDeviceSelector), value: device.id)
            if alertsFollowedDefault {
                // Alerts and sound effects were on the same device as everything else, so keep them together.
                try? AudioObjectID.system.write(
                    AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultSystemOutputDevice), value: device.id
                )
            }
        } catch {
            Log.devices.error("Could not switch to \(device.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
