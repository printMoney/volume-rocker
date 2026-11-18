import CoreAudio
import Foundation

/// One process that Core Audio knows about.
struct AudioProcess: Equatable, Sendable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
    /// Devices this process is currently playing to.
    let outputDeviceIDs: [AudioDeviceID]
}

/// Watches Core Audio's process list and each process's "is running output" state, live.
@MainActor
final class AudioProcessMonitor {
    var onChange: (([AudioProcess]) -> Void)?
    private(set) var processes: [AudioProcess] = []

    private var listListener: PropertyListener?
    private var processListeners: [AudioObjectID: [PropertyListener]] = [:]
    private var reloadScheduled = false

    func start() {
        listListener = PropertyListener(
            objectID: .system,
            address: AudioObjectPropertyAddress(kAudioHardwarePropertyProcessObjectList)
        ) { [weak self] in self?.scheduleReload() }
        reload()
    }

    /// Re-reads all processes and reports them, even if nothing changed.
    func refresh() {
        processes = []
        reload()
    }

    func stop() {
        listListener = nil
        processListeners.removeAll()
    }

    /// Coalesces bursts of notifications (e.g. a browser starting several helpers) into one reload.
    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        Task { @MainActor [weak self] in
            self?.reloadScheduled = false
            self?.reload()
        }
    }

    private func reload() {
        let address = AudioObjectPropertyAddress(kAudioHardwarePropertyProcessObjectList)
        let objectIDs = (try? AudioObjectID.system.readArray(address, of: AudioObjectID.self)) ?? []
        let current = Set(objectIDs)

        for objectID in processListeners.keys where !current.contains(objectID) {
            processListeners[objectID] = nil
        }
        for objectID in objectIDs where processListeners[objectID] == nil {
            // macOS doesn't reliably notify about IsRunningOutput changes (tested on macOS 26/27), but it does
            // notify about IsRunning, and by then IsRunningOutput is already up to date. So watch both.
            processListeners[objectID] = [
                kAudioProcessPropertyIsRunning,
                kAudioProcessPropertyIsRunningOutput,
                kAudioProcessPropertyDevices,
            ].compactMap { selector in
                PropertyListener(objectID: objectID, address: AudioObjectPropertyAddress(selector)) { [weak self] in
                    self?.scheduleReload()
                }
            }
        }

        let updated = objectIDs.compactMap(Self.readProcess)
        guard updated != processes else { return }
        processes = updated
        onChange?(updated)
    }

    private static func readProcess(_ objectID: AudioObjectID) -> AudioProcess? {
        guard let pid = try? objectID.read(AudioObjectPropertyAddress(kAudioProcessPropertyPID), default: pid_t(-1)),
              pid > 0
        else { return nil }
        let bundleID = try? objectID.readString(AudioObjectPropertyAddress(kAudioProcessPropertyBundleID))
        let running = (try? objectID.read(AudioObjectPropertyAddress(kAudioProcessPropertyIsRunningOutput), default: UInt32(0))) ?? 0
        let devicesAddress = AudioObjectPropertyAddress(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
        let devices = (try? objectID.readArray(devicesAddress, of: AudioDeviceID.self)) ?? []
        return AudioProcess(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID?.isEmpty == false ? bundleID : nil,
            isRunningOutput: running != 0,
            outputDeviceIDs: devices
        )
    }
}
