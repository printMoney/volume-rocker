import SwiftUI

/// App entry point. Volume Rocker lives only in the menu bar (`LSUIElement`), so there is no Dock icon
/// and no main window, just the mixer panel and a separate Settings window.
@main
struct VolumeRockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MixerPanelView(model: appDelegate.model)
        } label: {
            MenuBarIcon(output: appDelegate.model.output)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model, updates: appDelegate.updates, loginItem: appDelegate.loginItem)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()
    let updates = UpdateController()
    let loginItem = LoginItem()
    private let onboarding = OnboardingWindowController()
    private lazy var statusItem = StatusItemController(model: model)
    private lazy var shortcuts = ShortcutController(model: model, statusItem: statusItem)
    private var distributedObservers: [any NSObjectProtocol] = []

    override init() {
        super.init()
        AppServices.model = model
    }

    /// Unit tests launch the app as their host; don't touch real audio then.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard !isRunningTests else { return }
        model.start()
        statusItem.start()
        shortcuts.start()
        model.onProfilesChanged = { [weak self] in self?.shortcuts.refreshProfileShortcuts() }
        observeControlCenterRequests()
        if !model.hasCompletedOnboarding {
            onboarding.show(model: model, loginItem: loginItem)
        }
    }

    /// The Control Center control runs in a separate, sandboxed process. It asks the app to act by posting
    /// distributed notifications without any data attached.
    private func observeControlCenterRequests() {
        let center = DistributedNotificationCenter.default()
        distributedObservers = [
            center.addObserver(forName: ControlCenterRequest.nextProfile, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.applyNextProfile() }
            },
            center.addObserver(forName: ControlCenterRequest.openMixer, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.statusItem.togglePanel() }
            },
        ]
    }

    func applicationDidBecomeActive(_: Notification) {
        guard !isRunningTests else { return }
        // The user may have changed the permission or login item in System Settings.
        model.refreshPermission()
        loginItem.refresh()
    }

    func applicationWillTerminate(_: Notification) {
        model.shutdown()
    }
}
