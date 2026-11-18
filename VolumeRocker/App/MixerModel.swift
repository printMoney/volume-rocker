import AppKit
import CoreAudio
import Observation

/// The app's central model: which apps are playing, their volumes, the output device and the permission state.
/// It turns all of that into a list of `TapRequest`s for the audio engine.
@MainActor
@Observable
final class MixerModel {
    /// How long a tap stays alive after an app goes quiet.
    static let idleGrace: TimeInterval = 30

    let output = OutputDeviceController()
    private(set) var apps: [AppAudioItem] = []
    private(set) var permission: AudioCapturePermission.Status = .unknown
    private(set) var hasCompletedOnboarding: Bool

    var showRecentApps: Bool {
        didSet { defaults.set(showRecentApps, forKey: Keys.showRecentApps) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: AppVolumeStore
    @ObservationIgnored private let monitor = AudioProcessMonitor()
    @ObservationIgnored private let resolver = AppResolver()
    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private var itemsByID: [String: AppAudioItem] = [:]
    @ObservationIgnored private var syncInFlight = false
    @ObservationIgnored private var syncPending = false
    @ObservationIgnored private var isStarted = false

    private enum Keys {
        static let showRecentApps = "showRecentApps"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = AppVolumeStore(defaults: defaults)
        showRecentApps = defaults.bool(forKey: Keys.showRecentApps)
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
        output.onDeviceChange = { [weak self] in self?.requestEngineSync() }
        output.start()
        monitor.onChange = { [weak self] processes in self?.update(with: processes) }
        monitor.start()
    }

    func shutdown() {
        store.flush()
        monitor.stop()
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
        store.set(setting, for: item.id)
    }

    func toggleMute(_ item: AppAudioItem) {
        var setting = item.setting
        setting.isMuted.toggle()
        item.apply(setting)
        store.set(setting, for: item.id)
    }

    // MARK: Process updates

    private func update(with processes: [AudioProcess]) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier
        let now = Date()

        struct Group {
            var app: ResolvedApp
            var objectIDs: [AudioObjectID] = []
            var isPlaying = false
            var outputDevice: AudioDeviceID?
        }
        var groups: [String: Group] = [:]

        for process in processes where process.pid != ownPID {
            let app = resolver.resolve(pid: process.pid, bundleID: process.bundleID)
            guard app.id != ownBundleID else { continue }
            var group = groups[app.id] ?? Group(app: app)
            group.objectIDs.append(process.objectID)
            if process.isRunningOutput {
                group.isPlaying = true
                group.outputDevice = group.outputDevice ?? process.outputDeviceIDs.first
            }
            groups[app.id] = group
        }
        resolver.prune(keeping: Set(processes.map(\.pid)))

        for (id, group) in groups {
            let item = itemsByID[id] ?? AppAudioItem(app: group.app, setting: store.setting(for: id))
            itemsByID[id] = item
            item.processObjectIDs = group.objectIDs.sorted()
            if group.isPlaying {
                item.outputDeviceID = group.outputDevice
            }
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
        guard canControlApps, output.deviceID.isValid else { return [] }
        let now = Date()
        return apps.compactMap { item in
            guard item.needsTap(at: now, grace: Self.idleGrace), !item.processObjectIDs.isEmpty else { return nil }
            let device = resolveOutputDevice(item.outputDeviceID)
            return TapRequest(
                key: item.id,
                processObjectIDs: item.processObjectIDs,
                outputDeviceID: device.id,
                outputDeviceUID: device.uid,
                renderState: item.renderState
            )
        }
    }

    /// Plays an app's audio on the device it was already using, falling back to the default output.
    private func resolveOutputDevice(_ deviceID: AudioDeviceID?) -> (id: AudioDeviceID, uid: String) {
        if let deviceID, deviceID.isValid,
           let uid = try? deviceID.deviceUID(), !uid.isEmpty,
           !uid.hasPrefix(AudioEngine.aggregateUIDPrefix) {
            return (deviceID, uid)
        }
        return (output.deviceID, output.deviceUID)
    }
}
