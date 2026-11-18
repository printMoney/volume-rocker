import AppKit
import CoreAudio
import Observation

/// The app's central model: which apps are playing, their volumes, the devices and the permission state.
/// It turns all of that into a list of `TapRequest`s for the audio engine.
@MainActor
@Observable
final class MixerModel {
    /// How long a tap stays alive after an app goes quiet.
    static let idleGrace: TimeInterval = 30
    /// How long to wait after wake before rebuilding taps, so devices (especially Bluetooth) can reconnect.
    static let wakeDelay: Duration = .seconds(2)

    let output = DefaultDeviceController(direction: .output)
    let input = DefaultDeviceController(direction: .input)
    let devices = AudioDeviceList()
    private(set) var apps: [AppAudioItem] = []
    private(set) var permission: AudioCapturePermission.Status = .unknown
    private(set) var hasCompletedOnboarding: Bool

    var showRecentApps: Bool {
        didSet { defaults.set(showRecentApps, forKey: Keys.showRecentApps) }
    }

    var showInputControls: Bool {
        didSet { defaults.set(showInputControls, forKey: Keys.showInputControls) }
    }

    /// Remember different app volumes for each output device (e.g. headphones vs. speakers).
    var rememberVolumesPerDevice: Bool {
        didSet {
            defaults.set(rememberVolumesPerDevice, forKey: Keys.rememberVolumesPerDevice)
            refreshSettingsScopes()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: AppVolumeStore
    @ObservationIgnored private let monitor = AudioProcessMonitor()
    @ObservationIgnored private let resolver = AppResolver()
    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private let systemEvents = SystemAudioEvents()
    @ObservationIgnored private var itemsByID: [String: AppAudioItem] = [:]
    @ObservationIgnored private var syncInFlight = false
    @ObservationIgnored private var syncPending = false
    @ObservationIgnored private var isStarted = false
    /// True while the Mac sleeps: all taps are released so apps play normally and devices can sleep.
    @ObservationIgnored private var isSuspended = false
    /// Bumped to rebuild every tap (after wake or an audio system restart).
    @ObservationIgnored private var globalGeneration = 0
    /// Bumped per output device UID to rebuild its taps (after a sample-rate change).
    @ObservationIgnored private var deviceGenerations: [String: Int] = [:]

    private enum Keys {
        static let showRecentApps = "showRecentApps"
        static let showInputControls = "showInputControls"
        static let rememberVolumesPerDevice = "rememberVolumesPerDevice"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = AppVolumeStore(defaults: defaults)
        showRecentApps = defaults.bool(forKey: Keys.showRecentApps)
        showInputControls = defaults.object(forKey: Keys.showInputControls) as? Bool ?? true
        rememberVolumesPerDevice = defaults.bool(forKey: Keys.rememberVolumesPerDevice)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    // MARK: Derived state

    /// Apps shown in the panel: playing apps, plus quiet ones if "Show Recent Apps" is on.
    var visibleApps: [AppAudioItem] {
        apps.filter { $0.isPlaying || (showRecentApps && ($0.hasPlayed || $0.isRegularApp)) }
    }

    /// Whether we may create taps. Without permission a tap would silence the app, so never risk it.
    var canControlApps: Bool {
        switch permission {
        case .authorized: true
        case .unknown: hasCompletedOnboarding
        case .denied, .notDetermined: false
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        permission = AudioCapturePermission.status()

        output.onDeviceChange = { [weak self] in self?.outputDeviceDidChange() }
        output.start()
        input.start()

        devices.onDevicesChanged = { [weak self] in self?.requestEngineSync() }
        devices.onSampleRateChanged = { [weak self] uid in self?.rebuildTaps(onDeviceUID: uid) }
        devices.start()

        monitor.onChange = { [weak self] processes in self?.update(with: processes) }
        monitor.start()

        systemEvents.onSleep = { [weak self] in self?.willSleep() }
        systemEvents.onWake = { [weak self] in self?.didWake() }
        systemEvents.onAudioServiceRestart = { [weak self] in self?.audioServiceDidRestart() }
        systemEvents.start()
    }

    func shutdown() {
        store.flush()
        monitor.stop()
        systemEvents.stop()
        Task { await engine.stopAll() }
    }

    func refreshPermission() {
        permission = AudioCapturePermission.status()
        requestEngineSync()
    }

    func requestPermission() async {
        let result = await AudioCapturePermission.request()
        permission = result == .unknown ? AudioCapturePermission.status() : result
        requestEngineSync()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Keys.hasCompletedOnboarding)
        requestEngineSync()
    }

    // MARK: User actions

    func setVolume(_ volume: Float, for item: AppAudioItem) {
        var setting = item.setting
        setting.volume = min(1, max(0, volume))
        if setting.volume > 0 {
            setting.isMuted = false
        }
        item.apply(setting)
        store.set(setting, for: item.id, deviceUID: item.settingsDeviceUID)
    }

    func toggleMute(_ item: AppAudioItem) {
        var setting = item.setting
        setting.isMuted.toggle()
        item.apply(setting)
        store.set(setting, for: item.id, deviceUID: item.settingsDeviceUID)
    }

    func select(_ device: AudioDevice, for direction: AudioDirection) {
        devices.makeDefault(device, for: direction)
    }

    // MARK: System events

    private func outputDeviceDidChange() {
        refreshSettingsScopes()
        requestEngineSync()
    }

    private func willSleep() {
        Log.devices.info("Sleeping: releasing all taps")
        isSuspended = true
        requestEngineSync()
    }

    private func didWake() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.wakeDelay)
            guard let self else { return }
            Log.devices.info("Woke: rebuilding taps")
            isSuspended = false
            globalGeneration += 1
            devices.reload(notify: false)
            requestEngineSync()
        }
    }

    /// `coreaudiod` restarted, so every object ID we hold is stale. Start over from scratch.
    private func audioServiceDidRestart() {
        Log.devices.notice("Core Audio restarted: resetting")
        Task { await engine.stopAll() }
        globalGeneration += 1
        monitor.stop()
        devices.stop()
        output.restart()
        input.restart()
        devices.start()
        monitor.start()
    }

    private func rebuildTaps(onDeviceUID uid: String) {
        deviceGenerations[uid, default: 0] += 1
        requestEngineSync()
    }

    // MARK: Process updates

    private struct ProcessGroup {
        var app: ResolvedApp
        var objectIDs: [AudioObjectID] = []
        var isPlaying = false
        var outputDevice: AudioDeviceID?
    }

    /// Groups processes by the app they belong to, skipping Volume Rocker itself.
    private func group(_ processes: [AudioProcess]) -> [String: ProcessGroup] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier
        var groups: [String: ProcessGroup] = [:]
        for process in processes where process.pid != ownPID {
            let app = resolver.resolve(pid: process.pid, bundleID: process.bundleID)
            guard app.id != ownBundleID else { continue }
            var group = groups[app.id] ?? ProcessGroup(app: app)
            group.objectIDs.append(process.objectID)
            if process.isRunningOutput {
                group.isPlaying = true
                group.outputDevice = group.outputDevice ?? process.outputDeviceIDs.first
            }
            groups[app.id] = group
        }
        resolver.prune(keeping: Set(processes.map(\.pid)))
        return groups
    }

    private func update(with processes: [AudioProcess]) {
        let now = Date()
        let groups = group(processes)

        for (id, group) in groups {
            let item: AppAudioItem
            if let existing = itemsByID[id] {
                item = existing
            } else {
                item = AppAudioItem(app: group.app, setting: store.setting(for: id))
                itemsByID[id] = item
            }
            item.processObjectIDs = group.objectIDs.sorted()
            if group.isPlaying {
                item.outputDeviceID = group.outputDevice
            }
            refreshSettingsScope(of: item)
            let wasPlaying = item.isPlaying
            item.setPlaying(group.isPlaying, at: now)
            if wasPlaying, !group.isPlaying {
                scheduleIdleCheck()
            }
        }
        for id in itemsByID.keys where groups[id] == nil {
            itemsByID[id] = nil
        }

        let sorted = itemsByID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if sorted.map(\.id) != apps.map(\.id) {
            apps = sorted
        }
        let playing = sorted.filter(\.isPlaying).map(\.name).joined(separator: ", ")
        Log.processes.debug("Playing: [\(playing, privacy: .public)]")
        requestEngineSync()
    }

    private func scheduleIdleCheck() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleGrace + 1))
            self?.requestEngineSync()
        }
    }

    // MARK: Per-device settings

    private func refreshSettingsScopes() {
        for item in apps {
            refreshSettingsScope(of: item)
        }
    }

    /// With per-device memory on, applies the app's saved setting for the device it is playing on.
    private func refreshSettingsScope(of item: AppAudioItem) {
        let deviceUID = rememberVolumesPerDevice ? resolveOutputDevice(item.outputDeviceID).uid : nil
        guard deviceUID != item.settingsDeviceUID else { return }
        item.settingsDeviceUID = deviceUID
        item.apply(store.setting(for: item.id, deviceUID: deviceUID))
    }

    // MARK: Engine sync

    /// Sends the desired set of taps to the engine. Calls are serialized so an older plan can never
    /// overwrite a newer one.
    private func requestEngineSync() {
        syncPending = true
        guard !syncInFlight else { return }
        syncInFlight = true
        Task { @MainActor in
            while syncPending {
                syncPending = false
                await engine.apply(makeTapRequests())
            }
            syncInFlight = false
        }
    }

    private func makeTapRequests() -> [TapRequest] {
        guard canControlApps, !isSuspended, output.deviceID.isValid else { return [] }
        let now = Date()
        return apps.compactMap { item in
            guard item.needsTap(at: now, grace: Self.idleGrace), !item.processObjectIDs.isEmpty else { return nil }
            let device = resolveOutputDevice(item.outputDeviceID)
            guard device.id.isValid else { return nil }
            var request = TapRequest(
                key: item.id,
                processObjectIDs: item.processObjectIDs,
                outputDeviceID: device.id,
                outputDeviceUID: device.uid,
                renderState: item.renderState
            )
            request.generation = globalGeneration + deviceGenerations[device.uid, default: 0]
            return request
        }
    }

    /// Plays an app's audio on the device it was already using, if that is a real, connected output device.
    /// Otherwise (unknown, disconnected, or an automatic aggregate such as voice processing) uses the default.
    private func resolveOutputDevice(_ deviceID: AudioDeviceID?) -> (id: AudioDeviceID, uid: String) {
        if let deviceID, let device = devices.device(withID: deviceID), device.hasOutput {
            return (device.id, device.uid)
        }
        return (output.deviceID, output.deviceUID)
    }
}
