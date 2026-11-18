import AppKit
import CoreAudio

/// System events that affect audio: sleep, wake, and the Core Audio daemon restarting.
@MainActor
final class SystemAudioEvents {
    var onSleep: (@MainActor () -> Void)?
    var onWake: (@MainActor () -> Void)?
    /// `coreaudiod` restarted (it can crash or be restarted by the system). Every audio object ID is now invalid.
    var onAudioServiceRestart: (@MainActor () -> Void)?

    private var observers: [any NSObjectProtocol] = []
    private var restartListener: PropertyListener?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onSleep?() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onWake?() }
            },
        ]
        restartListener = PropertyListener(
            objectID: .system,
            address: AudioObjectPropertyAddress(kAudioHardwarePropertyServiceRestarted)
        ) { [weak self] in self?.onAudioServiceRestart?() }
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        restartListener = nil
    }
}
